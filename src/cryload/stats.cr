module Cryload
  # Stats holder for the benchmark
  class Stats
    HISTOGRAM_BUCKET_SIZE_MS =    1.0
    HISTOGRAM_MAX_MS         = 60_000
    HISTOGRAM_BUCKET_COUNT   = HISTOGRAM_MAX_MS + 1

    @ongoing_check_number : Int32
    @total_request_count : Int64
    @ok_requests : Int64
    @not_ok_requests : Int64
    @total_request_time_ms : Float64
    @min_request_time_ms : Float64
    @max_request_time_ms : Float64
    @mean_latency_ms : Float64
    @m2_latency_ms : Float64
    @latency_histogram : Array(Int64)
    @histogram_overflow_count : Int64
    @mutex : Mutex

    getter :request_number
    getter :ongoing_check_number
    getter :duration_mode
    getter :benchmark_start
    getter :url
    getter :json_output

    TIME_IN_MILISECONDS = 1000

    def initialize(@request_number : Int32, @duration_mode : Bool = false, @benchmark_start : Time::Instant = Time.instant, @url : String = "", @json_output : Bool = false)
      @total_request_count = 0_i64
      @ok_requests = 0_i64
      @not_ok_requests = 0_i64
      @total_request_time_ms = 0.0
      @min_request_time_ms = Float64::INFINITY
      @max_request_time_ms = 0.0
      @mean_latency_ms = 0.0
      @m2_latency_ms = 0.0
      @latency_histogram = Array(Int64).new(HISTOGRAM_BUCKET_COUNT, 0_i64)
      @histogram_overflow_count = 0_i64
      @mutex = Mutex.new
      @ongoing_check_number = @duration_mode ? 100 : {@request_number // 10, 1}.max
    end

    def min_request_time
      @mutex.synchronize do
        return 0.0 if @total_request_count == 0
        @min_request_time_ms
      end
    end

    def max_request_time
      @mutex.synchronize do
        return 0.0 if @total_request_count == 0
        @max_request_time_ms
      end
    end

    def average_request_time
      @mutex.synchronize do
        return 0.0 if @total_request_count == 0
        @total_request_time_ms / @total_request_count
      end
    end

    def latency_stdev
      @mutex.synchronize do
        return 0.0 if @total_request_count < 2
        variance = @m2_latency_ms / @total_request_count
        Math.sqrt(variance)
      end
    end

    # Requests per second = total requests / wall clock time (actual throughput)
    def request_per_second
      count = total_request_count
      return 0.0 if count == 0
      elapsed = (Time.instant - @benchmark_start).total_seconds
      elapsed > 0 ? count.to_f / elapsed : 0.0
    end

    # Wall clock time from benchmark start to now
    def wall_clock_seconds
      (Time.instant - @benchmark_start).total_seconds
    end

    def total_request_time_in_seconds
      total_request_time / TIME_IN_MILISECONDS
    end

    def ok_requests
      @mutex.synchronize { @ok_requests }
    end

    def not_ok_requests
      @mutex.synchronize { @not_ok_requests }
    end

    def empty?
      @mutex.synchronize { @total_request_count == 0 }
    end

    def total_request_count
      @mutex.synchronize { @total_request_count }
    end

    def p95_request_time
      percentile_request_time(95.0)
    end

    def p99_request_time
      percentile_request_time(99.0)
    end

    def <<(request : Request)
      record_request request.time_taken, request.is_ok?
    end

    def record_request(time_taken_ms : Float64, ok : Bool)
      @mutex.synchronize do
        @total_request_count += 1
        @total_request_time_ms += time_taken_ms
        @min_request_time_ms = {@min_request_time_ms, time_taken_ms}.min
        @max_request_time_ms = {@max_request_time_ms, time_taken_ms}.max
        if ok
          @ok_requests += 1
        else
          @not_ok_requests += 1
        end

        # Welford online variance: numerically stable and O(1) memory.
        delta = time_taken_ms - @mean_latency_ms
        @mean_latency_ms += delta / @total_request_count
        delta2 = time_taken_ms - @mean_latency_ms
        @m2_latency_ms += delta * delta2

        bucket_index = (time_taken_ms / HISTOGRAM_BUCKET_SIZE_MS).floor.to_i
        if bucket_index < HISTOGRAM_BUCKET_COUNT
          @latency_histogram[bucket_index] += 1
        else
          @histogram_overflow_count += 1
        end
      end
    end

    private def total_request_time
      @mutex.synchronize { @total_request_time_ms }
    end

    private def percentile_request_time(percentile : Float64)
      @mutex.synchronize do
        return 0.0 if @total_request_count == 0

        rank = (@total_request_count.to_f * (percentile / 100.0)).ceil.to_i64
        rank = 1_i64 if rank < 1
        seen = 0_i64

        @latency_histogram.each_with_index do |count, index|
          next if count == 0
          seen += count
          if seen >= rank
            return index.to_f * HISTOGRAM_BUCKET_SIZE_MS
          end
        end

        if seen + @histogram_overflow_count >= rank
          return HISTOGRAM_MAX_MS.to_f
        end

        @max_request_time_ms
      end
    end
  end

  def self.create_stats(request_number, duration_mode : Bool = false, benchmark_start : Time::Instant = Time.instant, url : String = "", json_output : Bool = false)
    @@stats = Stats.new request_number, duration_mode, benchmark_start, url, json_output
  end

  def self.stats
    @@stats.not_nil!
  end
end
