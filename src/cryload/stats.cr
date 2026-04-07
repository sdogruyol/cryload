module Cryload
  # Stats holder for the benchmark
  class Stats
    HISTOGRAM_BUCKET_SIZE_MS =    1.0
    HISTOGRAM_MAX_MS         = 60_000
    HISTOGRAM_BUCKET_COUNT   = HISTOGRAM_MAX_MS + 1

    # Worker-local stats batch flushed periodically to the global collector.
    class Batch
      @success_status_ranges : Array(Range(Int32, Int32))
      @total_request_count : Int64
      @response_count : Int64
      @ok_requests : Int64
      @not_ok_requests : Int64
      @transport_error_count : Int64
      @total_request_time_ms : Float64
      @min_request_time_ms : Float64
      @max_request_time_ms : Float64
      @mean_latency_ms : Float64
      @m2_latency_ms : Float64
      @latency_buckets : Hash(Int32, Int64)
      @histogram_overflow_count : Int64
      @status_code_counts : Hash(Int32, Int64)
      @error_counts : Hash(String, Int64)

      getter :total_request_count
      getter :response_count
      getter :ok_requests
      getter :not_ok_requests
      getter :transport_error_count
      getter :total_request_time_ms
      getter :min_request_time_ms
      getter :max_request_time_ms
      getter :mean_latency_ms
      getter :m2_latency_ms
      getter :latency_buckets
      getter :histogram_overflow_count
      getter :status_code_counts
      getter :error_counts

      def initialize(@success_status_ranges : Array(Range(Int32, Int32)) = [200..299])
        @total_request_count = 0_i64
        @response_count = 0_i64
        @ok_requests = 0_i64
        @not_ok_requests = 0_i64
        @transport_error_count = 0_i64
        @total_request_time_ms = 0.0
        @min_request_time_ms = Float64::INFINITY
        @max_request_time_ms = 0.0
        @mean_latency_ms = 0.0
        @m2_latency_ms = 0.0
        @latency_buckets = Hash(Int32, Int64).new(0_i64)
        @histogram_overflow_count = 0_i64
        @status_code_counts = Hash(Int32, Int64).new(0_i64)
        @error_counts = Hash(String, Int64).new(0_i64)
      end

      def empty?
        @total_request_count == 0
      end

      def record_response(time_taken_ms : Float64, status_code : Int32)
        @total_request_count += 1
        @response_count += 1
        @status_code_counts[status_code] += 1
        if success_status?(status_code)
          @ok_requests += 1
        else
          @not_ok_requests += 1
        end
        update_latency_metrics time_taken_ms
      end

      def record_error(time_taken_ms : Float64, category : String)
        @total_request_count += 1
        @transport_error_count += 1
        @error_counts[category] += 1
        update_latency_metrics time_taken_ms
      end

      private def update_latency_metrics(time_taken_ms : Float64)
        @total_request_time_ms += time_taken_ms
        @min_request_time_ms = {@min_request_time_ms, time_taken_ms}.min
        @max_request_time_ms = {@max_request_time_ms, time_taken_ms}.max

        delta = time_taken_ms - @mean_latency_ms
        @mean_latency_ms += delta / @total_request_count
        delta2 = time_taken_ms - @mean_latency_ms
        @m2_latency_ms += delta * delta2

        bucket_index = (time_taken_ms / HISTOGRAM_BUCKET_SIZE_MS).floor.to_i
        if bucket_index < HISTOGRAM_BUCKET_COUNT
          @latency_buckets[bucket_index] += 1
        else
          @histogram_overflow_count += 1
        end
      end

      private def success_status?(status_code : Int32)
        @success_status_ranges.any? { |status_range| status_range.includes?(status_code) }
      end
    end

    @ongoing_check_number : Int32
    @total_request_count : Int64
    @response_count : Int64
    @ok_requests : Int64
    @not_ok_requests : Int64
    @transport_error_count : Int64
    @total_request_time_ms : Float64
    @min_request_time_ms : Float64
    @max_request_time_ms : Float64
    @mean_latency_ms : Float64
    @m2_latency_ms : Float64
    @latency_histogram : Array(Int64)
    @histogram_overflow_count : Int64
    @status_code_counts : Hash(Int32, Int64)
    @error_counts : Hash(String, Int64)
    @mutex : Mutex

    getter :request_number
    getter :ongoing_check_number
    getter :duration_mode
    getter :benchmark_start
    getter :url
    getter :output_format
    getter :success_status_ranges
    getter :planned_duration_seconds

    TIME_IN_MILISECONDS = 1000

    def initialize(@request_number : Int32, @duration_mode : Bool = false, @benchmark_start : Time::Instant = Time.instant, @url : String = "", @output_format : String = "text", @success_status_ranges : Array(Range(Int32, Int32)) = [200..299], @planned_duration_seconds : Float64? = nil)
      @total_request_count = 0_i64
      @response_count = 0_i64
      @ok_requests = 0_i64
      @not_ok_requests = 0_i64
      @transport_error_count = 0_i64
      @total_request_time_ms = 0.0
      @min_request_time_ms = Float64::INFINITY
      @max_request_time_ms = 0.0
      @mean_latency_ms = 0.0
      @m2_latency_ms = 0.0
      @latency_histogram = Array(Int64).new(HISTOGRAM_BUCKET_COUNT, 0_i64)
      @histogram_overflow_count = 0_i64
      @status_code_counts = Hash(Int32, Int64).new(0_i64)
      @error_counts = Hash(String, Int64).new(0_i64)
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
      elapsed = effective_elapsed_seconds
      elapsed > 0 ? count.to_f / elapsed : 0.0
    end

    # Reported elapsed time for the benchmark window.
    def wall_clock_seconds
      effective_elapsed_seconds
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

    def p50_request_time
      percentile_request_time(50.0)
    end

    def p25_request_time
      percentile_request_time(25.0)
    end

    def p90_request_time
      percentile_request_time(90.0)
    end

    def p75_request_time
      percentile_request_time(75.0)
    end

    def p999_request_time
      percentile_request_time(99.9)
    end

    def p10_request_time
      percentile_request_time(10.0)
    end

    def response_count
      @mutex.synchronize { @response_count }
    end

    def transport_error_count
      @mutex.synchronize { @transport_error_count }
    end

    def status_code_counts
      @mutex.synchronize { @status_code_counts.dup }
    end

    def error_counts
      @mutex.synchronize { @error_counts.dup }
    end

    def latency_histogram_bins(bin_count : Int32 = 11)
      @mutex.synchronize do
        return [] of NamedTuple(start_ms: Float64, end_ms: Float64, count: Int64, percent: Float64) if @total_request_count == 0

        if (@max_request_time_ms - @min_request_time_ms) < HISTOGRAM_BUCKET_SIZE_MS
          return [{
            start_ms: @min_request_time_ms.round(2),
            end_ms: @max_request_time_ms.round(2),
            count: @total_request_count,
            percent: 100.0,
          }]
        end

        effective_bin_count = {1, bin_count}.max
        span_ms = @max_request_time_ms - @min_request_time_ms
        counts = Array(Int64).new(effective_bin_count, 0_i64)

        @latency_histogram.each_with_index do |count, index|
          next if count == 0

          bin_index = (((index.to_f - @min_request_time_ms) / span_ms) * effective_bin_count).floor.to_i
          bin_index = 0 if bin_index < 0
          bin_index = effective_bin_count - 1 if bin_index >= effective_bin_count
          counts[bin_index] += count
        end

        counts[effective_bin_count - 1] += @histogram_overflow_count

        bins = [] of NamedTuple(start_ms: Float64, end_ms: Float64, count: Int64, percent: Float64)
        effective_bin_count.times do |index|
          start_ms = @min_request_time_ms + (span_ms * index / effective_bin_count)
          end_ms = if index == effective_bin_count - 1
                     @max_request_time_ms
                   else
                     @min_request_time_ms + (span_ms * (index + 1) / effective_bin_count)
                   end
          bins << {
            start_ms: start_ms.round(2),
            end_ms: end_ms.round(2),
            count: counts[index],
            percent: ((counts[index].to_f / @total_request_count) * 100.0).round(2),
          }
        end

        bins
      end
    end

    def final_exit_code
      @mutex.synchronize do
        @transport_error_count > 0 && @response_count == 0 ? 1 : 0
      end
    end

    def json_output
      @output_format == "json"
    end

    def csv_output
      @output_format == "csv"
    end

    def quiet_output
      @output_format == "quiet"
    end

    def <<(request : Request)
      record_response request.time_taken, request.status_code
    end

    def record_response(time_taken_ms : Float64, status_code : Int32)
      batch = Batch.new(@success_status_ranges)
      batch.record_response time_taken_ms, status_code
      merge_batch batch
    end

    def record_error(time_taken_ms : Float64, category : String)
      batch = Batch.new(@success_status_ranges)
      batch.record_error time_taken_ms, category
      merge_batch batch
    end

    def merge_batch(batch : Batch)
      return if batch.empty?

      @mutex.synchronize do
        merge_batch_without_lock batch
      end
    end

    private def total_request_time
      @mutex.synchronize { @total_request_time_ms }
    end

    private def effective_elapsed_seconds
      elapsed = (Time.instant - @benchmark_start).total_seconds
      planned_duration_seconds = @planned_duration_seconds
      return elapsed unless @duration_mode && planned_duration_seconds

      {elapsed, planned_duration_seconds}.min
    end

    private def merge_batch_without_lock(batch : Batch)
      previous_count = @total_request_count
      batch_count = batch.total_request_count

      @total_request_count += batch_count
      @response_count += batch.response_count
      @ok_requests += batch.ok_requests
      @not_ok_requests += batch.not_ok_requests
      @transport_error_count += batch.transport_error_count
      @total_request_time_ms += batch.total_request_time_ms
      @min_request_time_ms = @min_request_time_ms.finite? ? {@min_request_time_ms, batch.min_request_time_ms}.min : batch.min_request_time_ms
      @max_request_time_ms = {@max_request_time_ms, batch.max_request_time_ms}.max

      if previous_count == 0
        @mean_latency_ms = batch.mean_latency_ms
        @m2_latency_ms = batch.m2_latency_ms
      elsif batch_count > 0
        combined_count = @total_request_count
        delta = batch.mean_latency_ms - @mean_latency_ms
        @mean_latency_ms += delta * batch_count / combined_count
        @m2_latency_ms += batch.m2_latency_ms + delta * delta * previous_count * batch_count / combined_count
      end

      batch.latency_buckets.each do |bucket_index, count|
        @latency_histogram[bucket_index] += count
      end
      @histogram_overflow_count += batch.histogram_overflow_count

      batch.status_code_counts.each do |status_code, count|
        @status_code_counts[status_code] += count
      end
      batch.error_counts.each do |category, count|
        @error_counts[category] += count
      end
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

  def self.create_stats(request_number, duration_mode : Bool = false, benchmark_start : Time::Instant = Time.instant, url : String = "", output_format : String = "text", success_status_ranges : Array(Range(Int32, Int32)) = [200..299], planned_duration_seconds : Float64? = nil)
    @@stats = Stats.new request_number, duration_mode, benchmark_start, url, output_format, success_status_ranges, planned_duration_seconds
  end

  def self.stats
    @@stats.not_nil!
  end
end
