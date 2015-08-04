module Cryload
  # Stats holder for the benchmark
  class Stats
    getter :total_request_count
    getter :request_number
    getter :ongoing_check_number
    property :requests

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
      total_request_time / @requests.count
    end

    def request_per_second
      1000 / average_request_time
    end

    def total_request_time_in_seconds
      total_request_time / 1000
    end

    def ok_requests
      request_statuses.select{|status| status == true}.count
    end

    def not_ok_requests
      request_statuses.select{|status| status == false}.count
    end

    private def total_request_time
      @requests.map(&.time_taken).sum
    end

    private def request_statuses
      @requests.map(&.is_ok?)
    end
  end
end
