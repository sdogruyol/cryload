require "./cryload/*"
require "http"
require "colorize"
require "option_parser"
require "json"
require "base64"

module Cryload
  DEFAULT_MAX_REDIRECTS = 5

  def self.create_http_client(uri, timeout_seconds : Int32? = nil, insecure : Bool = false)
    port = uri.port || (uri.scheme == "https" ? 443 : 80)
    tls_context = if uri.scheme == "https"
                    insecure ? OpenSSL::SSL::Context::Client.insecure : true
                  else
                    false
                  end
    client = HTTP::Client.new uri.host.not_nil!, port: port, tls: tls_context
    if (timeout = timeout_seconds)
      span = timeout.seconds
      client.connect_timeout = span
      client.read_timeout = span
    end
    client
  end

  class RateLimiter
    @interval : Time::Span
    @next_slot : Time::Instant
    @mutex : Mutex

    def initialize(rate_limit : Int32)
      @interval = Time::Span.new(nanoseconds: (1_000_000_000.0 / rate_limit).round.to_i64)
      @next_slot = Time.instant
      @mutex = Mutex.new
    end

    def acquire(deadline : Time::Instant? = nil) : Bool
      scheduled_at = Time.instant
      now = Time.instant

      @mutex.synchronize do
        now = Time.instant
        scheduled_at = @next_slot > now ? @next_slot : now
        return false if deadline && scheduled_at >= deadline
        @next_slot = scheduled_at + @interval
      end

      sleep_for = scheduled_at - now
      sleep sleep_for if sleep_for.positive?
      true
    end
  end

  # LoadGenerator is the main class in Cryload. It's responsible for generating
  # the requests and other major stuff.
  class LoadGenerator
    BATCH_FLUSH_SIZE = 250_i64
    @@connection_error_printed = false
    @@connection_error_mutex = Mutex.new

    # LoadGenerator: request mode (host, request_number, connections) or duration mode (host, connections, duration_seconds).
    def initialize(
      @host : String,
      request_number : Int32? = nil,
      @connections : Int32 = 10,
      duration_seconds : Int32? = nil,
      @json_output : Bool = false,
      @http_method : String = "GET",
      @http_body : String? = nil,
      @http_headers : HTTP::Headers = HTTP::Headers.new,
      @timeout_seconds : Int32? = nil,
      @insecure : Bool = false,
      @rate_limit : Int32? = nil,
      @follow_redirects : Bool = false,
    )
      @request_number = request_number || -1
      @duration_seconds = duration_seconds
      @duration_mode = !@duration_seconds.nil?

      Cryload.create_stats @request_number, @duration_mode, Time.instant, @host, @json_output
      worker_count = @duration_mode ? {1, @connections}.max : {1, {@connections, @request_number}.min}.max
      Logger.log_header @host, @duration_seconds, @request_number > 0 ? @request_number : nil, worker_count, @rate_limit
      request_channel, done_channel, worker_count = generate_request_channel
      spawn_receive_loop request_channel, done_channel, worker_count
    end

    # Generates request and done channels. Spawns workers (request count or duration based).
    def generate_request_channel
      stats_channel = Channel(Stats::Batch).new
      done_channel = Channel(Nil).new
      uri = parse_uri
      rate_limiter = create_rate_limiter
      worker_count = @duration_mode ? {1, @connections}.max : {1, {@connections, @request_number}.min}.max

      worker_count.times do |i|
        if @duration_mode
          spawn_duration_worker stats_channel, done_channel, uri, rate_limiter
        else
          spawn_request_worker stats_channel, done_channel, uri, i, worker_count, rate_limiter
        end
      end

      {stats_channel, done_channel, worker_count}
    end

    # Spawns a worker that runs for duration_seconds, making requests until time is up.
    def spawn_duration_worker(stats_channel, done_channel, uri, rate_limiter : RateLimiter?)
      spawn do
        client = create_http_client uri
        deadline = Time.instant + @duration_seconds.not_nil!.seconds
        local_batch = Stats::Batch.new

        while acquire_rate_slot(rate_limiter, deadline)
          create_request(client, uri, local_batch)
          local_batch = flush_batch_if_needed stats_channel, local_batch
        end

        flush_batch stats_channel, local_batch
        done_channel.send nil
      end
    end

    # Spawns a worker that makes its share of requests.
    def spawn_request_worker(stats_channel, done_channel, uri, worker_index, total_workers, rate_limiter : RateLimiter?)
      spawn do
        client = create_http_client uri
        requests_for_this_worker = requests_per_worker worker_index, total_workers
        local_batch = Stats::Batch.new

        requests_for_this_worker.times do
          acquire_rate_slot rate_limiter
          create_request(client, uri, local_batch)
          local_batch = flush_batch_if_needed stats_channel, local_batch
        end

        flush_batch stats_channel, local_batch
        done_channel.send nil
      end
    end

    # Distributes requests across workers. First (request_number % workers) get one extra.
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
      return Stats::Batch.new if local_batch.empty?

      stats_channel.send local_batch
      Stats::Batch.new
    end

    # Spawns the receiver loop. In request mode: receive until count reached.
    # In duration mode: use select to receive requests and worker-done signals.
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
      done_count = 0

      loop do
        select
        when batch = stats_channel.receive
          Cryload.stats.merge_batch batch
          ExecutionHandler.check_duration
        when done_channel.receive
          done_count += 1
          break if done_count >= worker_count
        end
      end

      Logger.log_final
      exit Cryload.stats.final_exit_code
    end

    # Parses the host string and converts it to an URI
    private def parse_uri
      uri = URI.parse(@host)
      unless uri.host && (uri.scheme == "http" || uri.scheme == "https")
        STDERR.puts "Invalid URL '#{@host}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
        exit 1
      end
      uri
    rescue URI::Error
      STDERR.puts "Invalid URL '#{@host}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
      exit 1
    end

    # Creates the HTTP client
    private def create_http_client(uri)
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      tls_context = if uri.scheme == "https"
                      @insecure ? OpenSSL::SSL::Context::Client.insecure : true
                    else
                      false
                    end
      Cryload.create_http_client uri, @timeout_seconds, @insecure
    end

    # Creates a new request to the given URI
    private def create_request(client, uri, local_batch : Stats::Batch)
      started_at = Time.instant
      request = Request.new client, uri, @http_method, @http_headers, @http_body, @timeout_seconds, @insecure, @follow_redirects
      local_batch.record_response request.time_taken, request.status_code
    rescue ex : Socket::Error | IO::Error | OpenSSL::SSL::Error
      elapsed_ms = (Time.instant - started_at.not_nil!).total_seconds * 1000.0
      local_batch.record_error elapsed_ms, ex.class.name.to_s
      host = uri.host || "localhost"
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
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
