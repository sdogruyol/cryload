require "random"

module Cryload
  class LoadGenerator
    BATCH_FLUSH_SIZE     = 250_i64
    BATCH_FLUSH_INTERVAL = 1.second
    DURATION_DRAIN_GRACE = 500.milliseconds
    PROGRESS_INTERVAL    = 1.second

    @@connection_error_printed = false
    @@connection_error_mutex = Mutex.new

    @workers : Int32
    @request_number : Int32
    @duration_mode : Bool

    def initialize(
      @host : String,
      request_number : Int32? = nil,
      @connections : Int32 = 10,
      @duration : Time::Span? = nil,
      @output_format : String = "text",
      http_method : String = "GET",
      http_body : String? = nil,
      @http_headers : HTTP::Headers = HTTP::Headers.new,
      @timeouts : Timeouts = Timeouts.new,
      @insecure : Bool = false,
      @rate_limit : Float64? = nil,
      follow_redirects : Bool = false,
      @success_status_ranges : Array(Range(Int32, Int32)) = [200..299],
      @ci_thresholds : CiThresholds = CiThresholds.new,
      @urls : Array(URI) = [] of URI,
      @warmup : Time::Span = Time::Span.zero,
      @proxy : URI? = nil,
      @progress : Bool = true,
      @random_path : Bool = false,
      @disable_keepalive : Bool = false,
      @latency_correction : Bool = true,
      workers : Int32? = nil,
    )
      @http_headers["Connection"] = "close" if @disable_keepalive
      @request_number = request_number || -1
      @duration_mode = !@duration.nil?
      @urls = [parse_uri(@host)] if @urls.empty?
      @uri_index = Atomic(Int64).new(0_i64)
      @spec = RequestSpec.new(
        method: http_method,
        body: http_body,
        timeouts: @timeouts,
        insecure: @insecure,
        follow_redirects: follow_redirects,
        proxy: @proxy,
      )

      fiber_count = @duration_mode ? {1, @connections}.max : {1, {@connections, @request_number}.min}.max
      # Never more OS threads than there are load fibers: a 96-core runner
      # driving `-c 4` gains nothing from 96 schedulers.
      @workers = {1, {workers || Fiber::ExecutionContext.default_workers_count, fiber_count}.min}.max
      Fiber::ExecutionContext.default.resize(@workers)

      config = RunConfig.new(
        workers: @workers,
        connections: @connections,
        rate_limit: @rate_limit,
        latency_correction: @latency_correction,
        keepalive: !@disable_keepalive,
        timeout: @timeouts.timeout,
        request_timeout: @timeouts.request_timeout,
        duration: @duration,
        warmup: @warmup,
        request_number: @request_number > 0 ? @request_number : nil,
      )

      Cryload.create_stats(
        @request_number, @duration_mode, Time.instant, @host, @output_format,
        @success_status_ranges, @ci_thresholds, @progress, config, @urls
      )
      Logger.log_header @host, fiber_count
      run_warmup fiber_count if @warmup > Time::Span.zero

      # The clock starts after warmup, so warmed-up connections do not eat into
      # the duration window and do not deflate the reported throughput.
      Cryload.stats.start_benchmark_window
      spawn_progress_ticker

      stats_channel, done_channel = spawn_workers fiber_count
      spawn_receive_loop stats_channel, done_channel, fiber_count
    end

    private def spawn_workers(fiber_count : Int32)
      stats_channel = Channel(Stats::Batch).new
      done_channel = Channel(Nil).new
      rate_limiter = create_rate_limiter
      deadline = Cryload.stats.deadline

      fiber_count.times do |index|
        if @duration_mode
          spawn_duration_worker stats_channel, done_channel, rate_limiter, deadline
        else
          spawn_request_worker stats_channel, done_channel, index, fiber_count, rate_limiter
        end
      end

      {stats_channel, done_channel}
    end

    # Everything a worker fiber owns exclusively: its keep-alive clients, its
    # scratch buffer for draining response bodies, its own copy of the request
    # headers (HTTP::Request mutates them) and its own PRNG.
    class Worker
      getter clients = Hash(String, PhasedClient).new
      getter buffer : Bytes
      getter headers : HTTP::Headers
      getter random : Random

      def initialize(headers : HTTP::Headers)
        @buffer = Request.buffer
        @headers = Cryload.clone_headers(headers)
        @random = Random.new
      end

      def close : Nil
        @clients.each_value(&.close)
        @clients.clear
      end

      def evict(origin : String) : Nil
        @clients.delete(origin).try(&.close)
      end
    end

    private def spawn_duration_worker(stats_channel, done_channel, rate_limiter : RateLimiter?, deadline : Time::Instant?)
      spawn do
        worker = Worker.new(@http_headers)
        batch = Cryload.stats.new_batch
        last_flush = Time.instant

        loop do
          scheduled_at, in_window = acquire_slot(rate_limiter, deadline)
          break unless in_window

          perform_request worker, batch, scheduled_at
          if flush_due?(batch, last_flush)
            batch = flush_batch stats_channel, batch
            last_flush = Time.instant
          end
        end

        worker.close
        flush_batch stats_channel, batch
        done_channel.send nil
      end
    end

    private def spawn_request_worker(stats_channel, done_channel, worker_index, total_workers, rate_limiter : RateLimiter?)
      spawn do
        worker = Worker.new(@http_headers)
        batch = Cryload.stats.new_batch
        last_flush = Time.instant

        requests_per_worker(worker_index, total_workers).times do
          scheduled_at, _ = acquire_slot(rate_limiter, nil)
          perform_request worker, batch, scheduled_at
          if flush_due?(batch, last_flush)
            batch = flush_batch stats_channel, batch
            last_flush = Time.instant
          end
        end

        worker.close
        flush_batch stats_channel, batch
        done_channel.send nil
      end
    end

    # Progress and a signal-time report only see merged batches, so a worker
    # whose whole quota is below BATCH_FLUSH_SIZE must still flush on a clock,
    # or a slow `-n` run reports zero requests until it ends.
    private def flush_due?(batch : Stats::Batch, last_flush : Time::Instant) : Bool
      batch.total_request_count >= BATCH_FLUSH_SIZE || (Time.instant - last_flush) >= BATCH_FLUSH_INTERVAL
    end

    # Reserves a schedule slot. The returned instant is what corrected latency
    # is measured from; the flag is false once the schedule has run past the
    # duration deadline and the worker should stop.
    private def acquire_slot(rate_limiter : RateLimiter?, deadline : Time::Instant?) : Tuple(Time::Instant?, Bool)
      if rate_limiter
        scheduled = rate_limiter.acquire(deadline)
        return {scheduled, !scheduled.nil?}
      end

      return {nil, Time.instant < deadline} if deadline
      {nil, true}
    end

    private def run_warmup(fiber_count)
      Logger.log_warmup @warmup
      done_channel = Channel(Nil).new
      deadline = Time.instant + @warmup

      fiber_count.times do
        spawn do
          worker = Worker.new(@http_headers)
          begin
            while Time.instant < deadline
              perform_warmup_request worker
            end
          ensure
            worker.close
          end
          done_channel.send nil
        end
      end

      fiber_count.times { done_channel.receive }
      @uri_index.set(0_i64)
    end

    private def next_target(worker : Worker) : Tuple(Int32, URI)
      index = (@uri_index.add(1) % @urls.size).to_i
      {index, apply_random_path(@urls[index], worker)}
    end

    # A per-worker PRNG is enough for cache busting and keeps the hot path off
    # Random::Secure, which pays a syscall per call and serialises across
    # threads once the load fibers run in parallel.
    private def apply_random_path(uri : URI, worker : Worker) : URI
      return uri unless @random_path

      token = worker.random.hex(4)
      path = uri.path.empty? ? "/#{token}" : "#{uri.path}/#{token}"
      URI.new(scheme: uri.scheme, host: uri.host, port: uri.port, path: path, query: uri.query)
    end

    private def client_for(uri : URI) : PhasedClient
      Cryload.create_http_client uri, @timeouts, @insecure, @proxy
    end

    # Reuses one keep-alive client per origin within a worker, so multi-URL
    # and --random-path runs don't pay a TCP/TLS handshake per request.
    private def pooled_client(worker : Worker, uri : URI) : PhasedClient
      worker.clients[origin_key(uri)] ||= client_for(uri)
    end

    # With --disable-keepalive every request gets a fresh client, so the
    # connection setup cost is part of the measured latency.
    private def perform_request(worker : Worker, batch : Stats::Batch, scheduled_at : Time::Instant?)
      url_index, uri = next_target worker
      fresh = @disable_keepalive
      client = fresh ? client_for(uri) : pooled_client(worker, uri)

      begin
        request = Request.new client, uri, @spec, worker.headers, worker.buffer, scheduled_at
        batch.record Stats::Sample.new(
          url_index: url_index,
          status_code: request.status_code,
          total_ms: request.total_ms,
          corrected_ms: request.corrected_ms,
          send_delay_ms: request.send_delay_ms,
          ttfb_ms: request.ttfb_ms,
          response_bytes: request.response_bytes,
          dns_ms: request.dns_ms,
          connect_ms: request.connect_ms,
          tls_ms: request.tls_ms,
        )
      rescue ex : Exception
        # The connection state is unknown after a failure (a body drain may have
        # been aborted mid-stream), so a pooled client is dropped rather than
        # reused for the next request.
        worker.evict origin_key(uri) unless fresh
        record_failure batch, ex, uri, url_index
      ensure
        client.close if fresh
      end
    end

    private def record_failure(batch : Stats::Batch, ex : Exception, uri : URI, url_index : Int32)
      batch.record_error url_index, ErrorCategory.of(ex), ex.message
      report_first_connection_error ex, uri
    end

    # One diagnostic line for the first unreachable-target error, so a typo in
    # the URL is obvious without drowning the log in identical messages.
    private def report_first_connection_error(ex : Exception, uri : URI)
      return unless ex.is_a?(Socket::Error | IO::Error | OpenSSL::SSL::Error)
      return if @@connection_error_printed

      @@connection_error_mutex.synchronize do
        next if @@connection_error_printed
        @@connection_error_printed = true
        Logger.log_connection_error uri, ex
      end
    end

    private def perform_warmup_request(worker : Worker)
      _, uri = next_target worker
      fresh = @disable_keepalive
      client = fresh ? client_for(uri) : pooled_client(worker, uri)

      begin
        Request.new client, uri, @spec, worker.headers, worker.buffer, nil
      rescue
        worker.evict origin_key(uri) unless fresh
      ensure
        client.close if fresh
      end
    end

    private def origin_key(uri : URI) : String
      "#{uri.scheme}://#{uri.host}:#{Cryload.effective_port(uri)}"
    end

    private def duration : Time::Span
      @duration || raise "Duration not set"
    end

    private def requests_per_worker(worker_index, total_workers)
      base = @request_number // total_workers
      remainder = @request_number % total_workers
      worker_index < remainder ? base + 1 : base
    end

    private def create_rate_limiter : RateLimiter?
      @rate_limit.try { |rate| RateLimiter.new(rate, Cryload.stats.benchmark_start) }
    end

    # Time-based progress: a ticker fiber refreshes the line once per second,
    # independent of how often worker batches arrive. The process exits via
    # ShutdownCoordinator.finish, which stops the ticker with it.
    private def spawn_progress_ticker
      return unless Cryload.stats.progress_enabled? && Cryload.stats.text_output?

      spawn do
        loop do
          sleep PROGRESS_INTERVAL
          Logger.log_progress
        end
      end
    end

    private def flush_batch(stats_channel, batch : Stats::Batch)
      return Cryload.stats.new_batch if batch.empty?

      stats_channel.send batch
      Cryload.stats.new_batch
    end

    private def spawn_receive_loop(stats_channel, done_channel, fiber_count)
      if @duration_mode
        spawn_receive_loop_duration stats_channel, done_channel, fiber_count
      else
        spawn_receive_loop_requests stats_channel, done_channel, fiber_count
      end
    end

    private def spawn_receive_loop_requests(stats_channel, done_channel, fiber_count)
      done_count = 0
      finished = false

      until finished
        select
        when batch = stats_channel.receive
          Cryload.stats.merge_batch batch
          finished = request_target_reached?
        when done_channel.receive
          done_count += 1
          finished = true if done_count >= fiber_count
        end
      end

      ShutdownCoordinator.finish
    end

    private def spawn_receive_loop_duration(stats_channel, done_channel, fiber_count)
      deadline = Cryload.stats.benchmark_start + duration
      done_count = 0
      draining = false
      drain_deadline = Time.instant
      finished = false

      until finished
        if draining
          finished, done_count = duration_drain_step(
            stats_channel, done_channel, drain_deadline, done_count, fiber_count, finished
          )
        else
          draining, drain_deadline, finished, done_count = duration_active_step(
            stats_channel, done_channel, deadline, done_count, fiber_count, draining, drain_deadline, finished
          )
        end
      end

      # A rate-limited run can drain its whole schedule before the deadline; the
      # window the user asked for is still the measurement window, otherwise
      # throughput would be divided by the few milliseconds the workers took.
      Cryload.stats.mark_benchmark_end deadline
      ShutdownCoordinator.finish
    end

    private def duration_drain_step(stats_channel, done_channel, drain_deadline, done_count, fiber_count, finished)
      remaining = drain_deadline - Time.instant
      return {true, done_count} unless remaining.positive?

      select
      when batch = stats_channel.receive
        Cryload.stats.merge_batch batch
      when done_channel.receive
        done_count += 1
        finished = true if done_count >= fiber_count
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
      fiber_count,
      draining,
      drain_deadline,
      finished,
    )
      remaining = deadline - Time.instant
      return begin_duration_drain(done_count, finished) unless remaining.positive?

      select
      when batch = stats_channel.receive
        Cryload.stats.merge_batch batch
      when done_channel.receive
        done_count += 1
        finished = true if done_count >= fiber_count
      when timeout(remaining)
        return begin_duration_drain(done_count, finished)
      end

      {draining, drain_deadline, finished, done_count}
    end

    private def begin_duration_drain(done_count, finished)
      Cryload.stats.mark_benchmark_end
      {true, Time.instant + DURATION_DRAIN_GRACE, finished, done_count}
    end

    private def request_target_reached? : Bool
      target = @request_number
      return false unless target > 0
      Cryload.stats.total_request_count >= target.to_i64
    end

    private def parse_uri(url : String)
      uri = URI.parse(url)
      unless uri.host && (uri.scheme == "http" || uri.scheme == "https")
        Logger.abort_with_config_error "Invalid URL '#{url}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
      end
      uri
    rescue URI::Error
      Logger.abort_with_config_error "Invalid URL '#{url}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
    end
  end
end
