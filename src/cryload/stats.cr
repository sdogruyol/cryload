module Cryload
  # Stats holder for the benchmark
  class Stats
    REQUESTS = [] of Request

    @ongoing_check_number : Int32

    getter :total_request_count
    getter :request_number
    getter :ongoing_check_number
    getter :duration_mode
    getter :benchmark_start

    TIME_IN_MILISECONDS = 1000

    def initialize(@request_number : Int32, @duration_mode : Bool = false, @benchmark_start : Time::Instant = Time.instant)
      @total_request_count = 0
      @ongoing_check_number = @duration_mode ? 100 : {@request_number // 10, 1}.max
    end

    def min_request_time
      REQUESTS.map(&.time_taken.as(Float64)).min
    end

    def max_request_time
      REQUESTS.map(&.time_taken.as(Float64)).max
    end

    def average_request_time
      total_request_time / REQUESTS.size
    end

    # Requests per second = total requests / wall clock time (actual throughput)
    def request_per_second
      return 0.0 if REQUESTS.empty?
      elapsed = (Time.instant - @benchmark_start).total_seconds
      elapsed > 0 ? REQUESTS.size.to_f / elapsed : 0.0
    end

    # Wall clock time from benchmark start to now
    def wall_clock_seconds
      (Time.instant - @benchmark_start).total_seconds
    end

    def total_request_time_in_seconds
      total_request_time / TIME_IN_MILISECONDS
    end

    def ok_requests
      request_statuses.select { |status| status == true }.size
    end

    def not_ok_requests
      request_statuses.select { |status| status == false }.size
    end

    def requests
      REQUESTS
    end

    def <<(request)
      REQUESTS << request
    end

    private def total_request_time
      REQUESTS.map(&.time_taken.as(Float64)).sum
    end

    private def request_statuses
      REQUESTS.map(&.is_ok?.as(Bool))
    end
  end

  def self.create_stats(request_number, duration_mode : Bool = false, benchmark_start : Time::Instant = Time.instant)
    @@stats = Stats.new request_number, duration_mode, benchmark_start
  end

  def self.stats
    @@stats.not_nil!
  end
end
