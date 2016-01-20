module Cryload
  # Responsible for handling the execution.
  # If the request cycle is in progress it continues logging.
  # If the request cycle is complete it logs the final stats.
  # Otherwise if an int signal received the logs the ongoing final
  # stats and terminates the execution
  class ExecutionHandler
    # The main check for execution
    def self.check
      if Cryload.stats.requests.size == Cryload.stats.request_number
        Logger.log_final
        exit
      elsif (Cryload.stats.requests.size % Cryload.stats.ongoing_check_number == 0) &&
            Cryload.stats.requests.size != Cryload.stats.request_number &&
            Cryload.stats.requests.size != 0
        Logger.log_ongoing
      end
    end
  end
end
