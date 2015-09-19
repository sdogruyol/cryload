module Cryload
  # Stats holder for the benchmark
  class Stats
    getter :total_request_count
    getter :request_number
    getter :ongoing_check_number
    property :requests

    TIME_IN_MILISECONDS = 1000

    def initialize(@request_number)
      @total_request_count = 0
      @ongoing_check_number = @request_number / 10
      @requests = [] of Request
    end

    def min_request_time
      @requests.map(&.time_taken).min
    end

    def max_request_time
      @requests.map(&.time_taken).max
    end

    def average_request_time
      total_request_time / @requests.size
    end

    def request_per_second
      TIME_IN_MILISECONDS / average_request_time
    end

    def total_request_time_in_seconds
      total_request_time / TIME_IN_MILISECONDS
    end

    def ok_requests
      request_statuses.select{|status| status == true}.size
    end

    def not_ok_requests
      request_statuses.select{|status| status == false}.size
    end

    private def total_request_time
      @requests.map(&.time_taken).sum
    end

    private def request_statuses
      @requests.map(&.is_ok?)
    end
  end
end
