module Cryload
  class Logger

    def initialize(@stats)
      if @stats.total_request_count == @stats.request_number
        log_final
      elsif (@stats.total_request_count % @stats.ongoing_check_number == 0 ) && @stats.total_request_count != @stats.request_number && @stats.total_request_count != 0
        log_ongoing
      end
    end

    def log_ongoing
      p "Total request made: #{@stats.total_request_count}"
    end

    def log_final
      p "COMPLETED"
      p "Minimum time taken per request #{@stats.min_request_time.round(3)} ms"
      p "Maximum time taken per request #{@stats.max_request_time.round(3)} ms"
      p "Average time taken per request: #{@stats.average_request_time.round(3)} ms"
      p "Request per second: #{@stats.request_per_second}"
      p "Total request made: #{@stats.total_request_count}"
      p "Total time taken: #{@stats.total_request_time_in_seconds} seconds"
      exit
    end

  end
end
