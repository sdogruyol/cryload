module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the ongoing request and prints out total request made up until that time.
    def self.log_ongoing
      puts "Total request made: #{Cryload.stats.requests.size}".colorize.bold
    end

    # Logs the final Cryload.stats containing all the information.
    def self.log_final
      puts "Completed All Requests!".colorize(:green)
      puts "-------------------------------"
      puts "\nTime taken per request:".colorize.blue.bold
      puts "Min: #{Cryload.stats.min_request_time.round(3)} ms".colorize.bold
      puts "Max: #{Cryload.stats.max_request_time.round(3)} ms".colorize.bold
      puts "Average: #{Cryload.stats.average_request_time.round(3)} ms\n".colorize.bold
      puts "Requests Statistics:".colorize.blue.bold
      puts "Request p/s: #{Cryload.stats.request_per_second}".colorize.bold
      puts "2xx requests #{Cryload.stats.ok_requests}".colorize.bold
      puts "Non 2xx requests #{Cryload.stats.not_ok_requests}".colorize.bold
      puts "Total request made: #{Cryload.stats.requests.size}".colorize.bold
      puts "Total time taken: #{Cryload.stats.total_request_time_in_seconds} seconds".colorize.bold
    end
  end
end
