module Cryload
  # Responsible for handling the execution.
  # If the request cycle is in progress it continues logging.
  # If the request cycle is complete it logs the final stats.
  # Otherwise if an int signal received the logs the ongoing final
  # stats and terminates the execution
  class ExecutionHandler

    # The main check for execution
    def self.check_execution(stats)
      setup_trap_signal(stats)
      if stats.requests.size == stats.request_number
        Logger.log_final(stats)
        exit
      elsif (stats.requests.size % stats.ongoing_check_number == 0 ) && stats.requests.size != stats.request_number && stats.requests.size != 0
        Logger.log_ongoing(stats)
      end
    end

    # Setups the INT signal trap for logging the ongoing stats
    # and exit
    private def self.setup_trap_signal(stats)
      Signal::INT.trap {
        Logger.log_final(stats)
        exit
      }
    end
  end
end
