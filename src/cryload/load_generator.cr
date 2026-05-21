require "random"

module Cryload
  class LoadGenerator
    BATCH_FLUSH_SIZE = 250_i64
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
        deadline = Time.instant + @duration_seconds.not_nil!.seconds
        local_batch = Stats::Batch.new(@success_status_ranges)
        shared_client = client_for(@urls.first) unless client_per_request?

        while acquire_rate_slot(rate_limiter, deadline)
          uri = next_uri
          if client_per_request?
            client = client_for(uri)
            create_request(client, uri, local_batch)
            client.close
          else
            create_request(shared_client.not_nil!, uri, local_batch)
          end
          local_batch = flush_batch stats_channel, local_batch
        end

        shared_client.try &.close
        flush_batch stats_channel, local_batch
        done_channel.send nil
      end
    end

    def spawn_request_worker(stats_channel, done_channel, worker_index, total_workers, rate_limiter : RateLimiter?)
      spawn do
        requests_for_this_worker = requests_per_worker worker_index, total_workers
        local_batch = Stats::Batch.new(@success_status_ranges)
        shared_client = client_for(@urls.first) unless client_per_request?

        requests_for_this_worker.times do
          acquire_rate_slot rate_limiter
          uri = next_uri
          if client_per_request?
            client = client_for(uri)
            create_request(client, uri, local_batch)
            client.close
          else
            create_request(shared_client.not_nil!, uri, local_batch)
          end
          local_batch = flush_batch_if_needed stats_channel, local_batch
        end

        shared_client.try &.close
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
          local_client = client_for(@urls.first) unless client_per_request?
          begin
            while Time.instant < deadline
              uri = next_uri
              if client_per_request?
                client = client_for(uri)
                begin
                  Request.new client, uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects, @proxy
                rescue
                ensure
                  client.close
                end
              else
                begin
                  Request.new local_client.not_nil!, uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects, @proxy
                rescue
                end
              end
            end
          ensure
            local_client.try &.close
          end
          done_channel.send nil
        end
      end

      worker_count.times { done_channel.receive }
      @uri_index.set(0_i64)
    end

    private def next_uri : URI
      base = @urls[(@uri_index.add(1) % @urls.size).to_i].not_nil!
      apply_random_path(base)
    end

    private def apply_random_path(uri : URI) : URI
      return uri unless @random_path

      token = Random::Secure.hex(4)
      path = uri.path.empty? ? "/#{token}" : "#{uri.path}/#{token}"
      URI.new(scheme: uri.scheme, host: uri.host, port: uri.port, path: path, query: uri.query)
    end

    private def client_for(uri : URI)
      create_http_client uri
    end

    private def client_per_request? : Bool
      @urls.size > 1 || @random_path
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

      loop do
        select
        when batch = stats_channel.receive
          Cryload.stats.merge_batch batch
          ExecutionHandler.check
        when done_channel.receive
          done_count += 1
          break if done_count >= worker_count
        end
      end

      Logger.log_final
      exit Cryload.stats.final_exit_code
    end

    def spawn_receive_loop_duration(stats_channel, done_channel, worker_count)
      deadline = Cryload.stats.benchmark_start + @duration_seconds.not_nil!.seconds
      done_count = 0
      draining = false
      drain_deadline = Time.instant

      loop do
        if draining
          remaining = drain_deadline - Time.instant
          break unless remaining.positive?

          select
          when batch = stats_channel.receive
            Cryload.stats.merge_batch batch
          when done_channel.receive
            done_count += 1
            break if done_count >= worker_count
          when timeout(remaining)
            break
          end
        else
          remaining = deadline - Time.instant
          if remaining.positive?
            select
            when batch = stats_channel.receive
              Cryload.stats.merge_batch batch
              ExecutionHandler.check_duration
            when done_channel.receive
              done_count += 1
              break if done_count >= worker_count
            when timeout(remaining)
              Cryload.stats.mark_benchmark_end
              draining = true
              drain_deadline = Time.instant + DURATION_DRAIN_GRACE
            end
          else
            Cryload.stats.mark_benchmark_end
            draining = true
            drain_deadline = Time.instant + DURATION_DRAIN_GRACE
          end
        end
      end

      Logger.log_final
      exit Cryload.stats.final_exit_code
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

    private def create_http_client(uri)
      Cryload.create_http_client uri, @timeout_seconds, @insecure, @proxy
    end

    private def transport_error_category(ex : Exception) : String
      ex.class.name.to_s
    end

    private def create_request(client, uri, local_batch : Stats::Batch)
      started_at = Time.instant
      request = Request.new client, uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects, @proxy
      local_batch.record_response request.time_taken, request.status_code, request.response_bytes
    rescue ex : Exception
      elapsed_ms = (Time.instant - started_at.not_nil!).total_seconds * 1000.0
      local_batch.record_error elapsed_ms, transport_error_category(ex)
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
