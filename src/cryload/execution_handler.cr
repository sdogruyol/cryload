module Cryload
  class ExecutionHandler
    @@last_logged_count = 0_i64

    def self.check
      size = Cryload.stats.total_request_count
      target = Cryload.stats.request_number.to_i64
      if size == target
        Logger.log_final
        exit Cryload.stats.final_exit_code
      elsif should_log_progress?(size)
        Logger.log_progress
        @@last_logged_count = size
      end
    end

    def self.check_duration
      size = Cryload.stats.total_request_count
      if should_log_progress?(size)
        Logger.log_progress
        @@last_logged_count = size
      end
    end

    private def self.should_log_progress?(size : Int64) : Bool
      size > 0 &&
        Cryload.stats.progress_enabled &&
        (size % Cryload.stats.ongoing_check_number.to_i64 == 0) &&
        size > @@last_logged_count
    end
  end
end
