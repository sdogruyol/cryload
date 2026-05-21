module Cryload
  class ShutdownCoordinator
    @@last_logged_count = 0_i64

    def self.update_after_batch : Bool
      log_progress_if_needed
      request_target_reached?
    end

    def self.update_during_duration
      log_progress_if_needed
    end

    def self.finish
      Logger.log_final
      exit Cryload.stats.final_exit_code
    end

    private def self.request_target_reached? : Bool
      return false if Cryload.stats.duration_mode

      target = Cryload.stats.request_number
      return false unless target > 0

      Cryload.stats.total_request_count >= target.to_i64
    end

    private def self.log_progress_if_needed
      size = Cryload.stats.total_request_count
      return unless should_log_progress?(size)

      Logger.log_progress
      @@last_logged_count = size
    end

    private def self.should_log_progress?(size : Int64) : Bool
      size > 0 &&
        Cryload.stats.progress_enabled &&
        (size % Cryload.stats.ongoing_check_number.to_i64 == 0) &&
        size > @@last_logged_count
    end
  end
end
