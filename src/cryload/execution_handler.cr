module Cryload
  # Responsible for handling the execution.
  # If the request cycle is in progress it continues logging.
  # If the request cycle is complete it logs the final stats.
  # Otherwise if an int signal received the logs the ongoing final
  # stats and terminates the execution
  class ExecutionHandler
    @@last_logged_count = 0

    # The main check for execution (request count mode)
    def self.check
      size = Cryload.stats.requests.size
      if size == Cryload.stats.request_number
        Logger.log_final
        exit
      elsif size > 0 && size != Cryload.stats.request_number &&
            (size % Cryload.stats.ongoing_check_number == 0) &&
            size > @@last_logged_count
        Logger.log_ongoing
        @@last_logged_count = size
      end
    end

    # Check for duration mode - only log ongoing at intervals
    def self.check_duration
      size = Cryload.stats.requests.size
      if size > 0 &&
         (size % Cryload.stats.ongoing_check_number == 0) &&
         size > @@last_logged_count
        Logger.log_ongoing
        @@last_logged_count = size
      end
    end
  end
end
