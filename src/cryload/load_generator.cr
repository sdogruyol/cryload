require "random"

module Cryload
  class LoadGenerator
    BATCH_FLUSH_SIZE     = 250_i64
    BATCH_FLUSH_INTERVAL = 1.second
    DURATION_DRAIN_GRACE = 500.milliseconds
    @@connection_error_printed = false
    @@connection_error_mutex = Mutex.new

    def initialize(
      @host : String,
      request_number : Int32? = nil,
      @connections : Int32 = 10,
      duration_seconds : Int32? = nil,
      @output_format : String = "text",
      @http_method : String = "GET",
      @http_body : String? = nil,
      @http_headers : HTTP::Headers = HTTP::Headers.new,
      @timeout_seconds : Int32? = nil,
      @insecure : Bool = false,
      @rate_limit : Int32? = nil,
      @follow_redirects : Bool = false,
      @success_status_ranges : Array(Range(Int32, Int32)) = [200..299],
      @ci_thresholds : CiThresholds = CiThresholds.new,
      @urls : Array(URI) = [] of URI,
      @warmup_seconds : Int32 = 0,
      @proxy : URI? = nil,
      @progress : Bool = true,
      @random_path : Bool = false,
    )
      @request_number = request_number || -1
      @duration_seconds = duration_seconds
      @duration_mode = !@duration_seconds.nil?
      @urls = [parse_uri(@host)] if @urls.empty?
      @uri_index = Atomic(Int64).new(0_i64)
      worker_count = @duration_mode ? {1, @connections}.max : {1, {@connections, @request_number}.min}.max

      Cryload.create_stats @request_number, @duration_mode, Time.instant, @host, @output_format, @success_status_ranges, @ci_thresholds, @progress
      Logger.log_header @host, @duration_seconds, @request_number > 0 ? @request_number : nil, worker_count, @rate_limit, @warmup_seconds
      run_warmup worker_count if @warmup_seconds > 0

      request_channel, done_channel, worker_count = generate_request_channel worker_count
      spawn_receive_loop request_channel, done_channel, worker_count
    end

    def generate_request_channel(worker_count)
      stats_channel = Channel(Stats::Batch).new
      done_channel = Channel(Nil).new
      rate_limiter = create_rate_limiter

      worker_count.times do |i|
        if @duration_mode
          spawn_duration_worker stats_channel, done_channel, rate_limiter
        else
          spawn_request_worker stats_channel, done_channel, i, worker_count, rate_limiter
        end
      end

      {stats_channel, done_channel, worker_count}
    end

    def spawn_duration_worker(stats_channel, done_channel, rate_limiter : RateLimiter?)
      spawn do
        deadline = Time.instant + duration_seconds.seconds
        local_batch = Stats::Batch.new(@success_status_ranges)
        clients = {} of String => HTTP::Client
        last_flush = Time.instant

        while acquire_rate_slot(rate_limiter, deadline)
          uri = next_uri
          create_request(pooled_client(clients, uri), uri, local_batch)
          if local_batch.total_request_count >= BATCH_FLUSH_SIZE || (Time.instant - last_flush) >= BATCH_FLUSH_INTERVAL
            local_batch = flush_batch stats_channel, local_batch
            last_flush = Time.instant
          end
        end

        clients.each_value(&.close)
        flush_batch stats_channel, local_batch
        done_channel.send nil
      end
    end

    def spawn_request_worker(stats_channel, done_channel, worker_index, total_workers, rate_limiter : RateLimiter?)
      spawn do
        requests_for_this_worker = requests_per_worker worker_index, total_workers
        local_batch = Stats::Batch.new(@success_status_ranges)
        clients = {} of String => HTTP::Client

        requests_for_this_worker.times do
          acquire_rate_slot rate_limiter
          uri = next_uri
          create_request(pooled_client(clients, uri), uri, local_batch)
          local_batch = flush_batch_if_needed stats_channel, local_batch
        end

        clients.each_value(&.close)
        flush_batch stats_channel, local_batch
        done_channel.send nil
      end
    end

    private def run_warmup(worker_count)
      Logger.log_warmup @warmup_seconds
      done_channel = Channel(Nil).new
      deadline = Time.instant + @warmup_seconds.seconds

      worker_count.times do
        spawn do
          clients = {} of String => HTTP::Client
          begin
            while Time.instant < deadline
              uri = next_uri
              begin
                Request.new pooled_client(clients, uri), uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects, @proxy
              rescue
              end
            end
          ensure
            clients.each_value(&.close)
          end
          done_channel.send nil
        end
      end

      worker_count.times { done_channel.receive }
      @uri_index.set(0_i64)
    end

    private def next_uri : URI
      base = @urls[(@uri_index.add(1) % @urls.size).to_i]
      apply_random_path(base)
    end

    private def apply_random_path(uri : URI) : URI
      return uri unless @random_path

      token = Random::Secure.hex(4)
      path = uri.path.empty? ? "/#{token}" : "#{uri.path}/#{token}"
      URI.new(scheme: uri.scheme, host: uri.host, port: uri.port, path: path, query: uri.query)
    end

    private def client_for(uri : URI)
      Cryload.create_http_client uri, @timeout_seconds, @insecure, @proxy
    end

    # Reuses one keep-alive client per origin within a worker, so multi-URL
    # and --random-path runs don't pay a TCP/TLS handshake per request.
    private def pooled_client(clients : Hash(String, HTTP::Client), uri : URI) : HTTP::Client
      clients[origin_key(uri)] ||= client_for(uri)
    end

    private def origin_key(uri : URI) : String
      "#{uri.scheme}://#{uri.host}:#{Cryload.effective_port(uri)}"
    end

    private def duration_seconds : Int32
      @duration_seconds || raise "Duration seconds not set"
    end

    private def requests_per_worker(worker_index, total_workers)
      base = @request_number // total_workers
      remainder = @request_number % total_workers
      worker_index < remainder ? base + 1 : base
    end

    private def create_rate_limiter : RateLimiter?
      @rate_limit.try { |rate_limit| RateLimiter.new(rate_limit) }
    end

    private def acquire_rate_slot(rate_limiter : RateLimiter?, deadline : Time::Instant? = nil) : Bool
      return rate_limiter.acquire(deadline) if rate_limiter
      return Time.instant < deadline if deadline
      true
    end

    private def flush_batch_if_needed(stats_channel, local_batch : Stats::Batch)
      return local_batch if local_batch.total_request_count < BATCH_FLUSH_SIZE

      flush_batch stats_channel, local_batch
    end

    private def flush_batch(stats_channel, local_batch : Stats::Batch)
      return Stats::Batch.new(@success_status_ranges) if local_batch.empty?

      stats_channel.send local_batch
      Stats::Batch.new(@success_status_ranges)
    end

    def spawn_receive_loop(stats_channel, done_channel, worker_count)
      if @duration_mode
        spawn_receive_loop_duration stats_channel, done_channel, worker_count
      else
        spawn_receive_loop_requests stats_channel, done_channel, worker_count
      end
    end

    def spawn_receive_loop_requests(stats_channel, done_channel, worker_count)
      done_count = 0
      finished = false

      until finished
        select
        when batch = stats_channel.receive
          Cryload.stats.merge_batch batch
          finished = ShutdownCoordinator.update_after_batch
        when done_channel.receive
          done_count += 1
          finished = true if done_count >= worker_count
        end
      end

      ShutdownCoordinator.finish
    end

    def spawn_receive_loop_duration(stats_channel, done_channel, worker_count)
      deadline = Cryload.stats.benchmark_start + duration_seconds.seconds
      done_count = 0
      draining = false
      drain_deadline = Time.instant
      finished = false

      until finished
        if draining
          finished, done_count = duration_drain_step(
            stats_channel, done_channel, drain_deadline, done_count, worker_count, finished
          )
        else
          draining, drain_deadline, finished, done_count = duration_active_step(
            stats_channel, done_channel, deadline, done_count, worker_count, draining, drain_deadline, finished
          )
        end
      end

      ShutdownCoordinator.finish
    end

    private def duration_drain_step(stats_channel, done_channel, drain_deadline, done_count, worker_count, finished)
      remaining = drain_deadline - Time.instant
      return {true, done_count} unless remaining.positive?

      select
      when batch = stats_channel.receive
        Cryload.stats.merge_batch batch
      when done_channel.receive
        done_count += 1
        finished = true if all_workers_done?(done_count, worker_count)
      when timeout(remaining)
        finished = true
      end

      {finished, done_count}
    end

    private def duration_active_step(
      stats_channel,
      done_channel,
      deadline,
      done_count,
      worker_count,
      draining,
      drain_deadline,
      finished,
    )
      remaining = deadline - Time.instant
      return begin_duration_drain(done_count, finished) unless remaining.positive?

      select
      when batch = stats_channel.receive
        Cryload.stats.merge_batch batch
        ShutdownCoordinator.update_during_duration
      when done_channel.receive
        done_count += 1
        finished = true if all_workers_done?(done_count, worker_count)
      when timeout(remaining)
        return begin_duration_drain(done_count, finished)
      end

      {draining, drain_deadline, finished, done_count}
    end

    private def begin_duration_drain(done_count, finished)
      Cryload.stats.mark_benchmark_end
      {true, Time.instant + DURATION_DRAIN_GRACE, finished, done_count}
    end

    private def all_workers_done?(done_count, worker_count)
      done_count >= worker_count
    end

    private def parse_uri(url : String)
      uri = URI.parse(url)
      unless uri.host && (uri.scheme == "http" || uri.scheme == "https")
        STDERR.puts "Invalid URL '#{url}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
        exit 1
      end
      uri
    rescue URI::Error
      STDERR.puts "Invalid URL '#{url}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
      exit 1
    end

    private def transport_error_category(ex : Exception) : String
      ex.class.name.to_s
    end

    private def create_request(client, uri, local_batch : Stats::Batch)
      request = Request.new client, uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects, @proxy
      local_batch.record_response request.time_taken, request.status_code, request.response_bytes
    rescue ex : Exception
      local_batch.record_error transport_error_category(ex)
      if ex.is_a?(Socket::Error | IO::Error | OpenSSL::SSL::Error)
        host = uri.host || "localhost"
        port = Cryload.effective_port(uri)
        msg = ex.message.to_s
        @@connection_error_mutex.synchronize do
          unless @@connection_error_printed
            STDERR.puts "Connection failed: Could not reach #{host}:#{port}"
            STDERR.puts "  → #{msg}"
            STDERR.puts "  → Continuing and counting transport errors in the final report."
            @@connection_error_printed = true
          end
        end
      end
    end
  end
end
