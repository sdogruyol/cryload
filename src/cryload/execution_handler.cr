module Cryload
  class ExecutionHandler

    def self.check_execution(stats)
      setup_trap_signal(stats)
      if stats.requests.count == stats.request_number
        Logger.log_final(stats)
        exit
      elsif (stats.requests.count % stats.ongoing_check_number == 0 ) && stats.requests.count != stats.request_number && stats.requests.count != 0
        Logger.log_ongoing(stats)
      end
    end

    private def self.setup_trap_signal(stats)
      Signal::INT.trap {
        Logger.log_final(stats)
        exit
      }
    end

  end
end
