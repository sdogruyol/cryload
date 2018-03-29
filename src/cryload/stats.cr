module Cryload
  # Stats holder for the benchmark
  class Stats
    REQUESTS = [] of Request

    @ongoing_check_number : Int32

    getter :total_request_count
    getter :request_number
    getter :ongoing_check_number

    TIME_IN_MILISECONDS = 1000

    def initialize(@request_number : Int32)
      @total_request_count = 0
      @ongoing_check_number = @request_number / 10
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

    def request_per_second
      TIME_IN_MILISECONDS / average_request_time
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
      REQUESTS.map(&.ok?.as(Bool))
    end
  end

  def self.create_stats(request_number)
    @@stats = Stats.new request_number
  end

  def self.stats
    @@stats.not_nil!
  end
end
