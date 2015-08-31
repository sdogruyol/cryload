module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the ongoing request and prints out total request made up until that time.
    def self.log_ongoing(stats)
      puts "Total request made: #{stats.requests.count}".colorize.bold
    end

    # Logs the final stats containing all the information.
    def self.log_final(stats)
      puts "Completed All Requeasts!".colorize(:green)
      puts "-------------------------------"
      puts "\nTime taken per request:".colorize.blue.bold
      puts "Min: #{stats.min_request_time.round(3)} ms".colorize.bold
      puts "Max: #{stats.max_request_time.round(3)} ms".colorize.bold
      puts "Average: #{stats.average_request_time.round(3)} ms\n".colorize.bold
      puts "Requests Statistics:".colorize.blue.bold
      puts "Request p/s: #{stats.request_per_second}".colorize.bold
      puts "2xx requests #{stats.ok_requests}".colorize.bold
      puts "Non 2xx requests #{stats.not_ok_requests}".colorize.bold
      puts "Total request made: #{stats.requests.count}".colorize.bold
      puts "Total time taken: #{stats.total_request_time_in_seconds} seconds".colorize.bold
    end

  end
end
