module Cryload
  class Logger

    def initialize(@stats)
      setup_trap_signal
      if @stats.requests.count == @stats.request_number
        log_final
        exit
      elsif (@stats.requests.count % @stats.ongoing_check_number == 0 ) && @stats.requests.count != @stats.request_number && @stats.requests.count != 0
        log_ongoing
      end
    end

    def log_ongoing
      puts "Total request made: #{@stats.requests.count}".colorize.bold
    end

    def log_final
      puts "#{@stats.ok_requests}"
      puts "Completed All Requeasts!".colorize(:green)
      puts "-------------------------------"
      puts "\nTime taken per request:".colorize.blue.bold
      puts "Min: #{@stats.min_request_time.round(3)} ms".colorize.bold
      puts "Max: #{@stats.max_request_time.round(3)} ms".colorize.bold
      puts "Average: #{@stats.average_request_time.round(3)} ms\n".colorize.bold
      puts "Requests Statistics:".colorize.blue.bold
      puts "Request p/s: #{@stats.request_per_second}".colorize.bold
      puts "2xx requests #{@stats.ok_requests}".colorize.bold
      puts "Non 2xx requests #{@stats.not_ok_requests}".colorize.bold
      puts "Total request made: #{@stats.requests.count}".colorize.bold
      puts "Total time taken: #{@stats.total_request_time_in_seconds} seconds".colorize.bold
    end

    def setup_trap_signal
      Signal::INT.trap {
        log_final
        exit
      }
    end

  end
end
