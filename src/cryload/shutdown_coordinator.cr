module Cryload
  class ShutdownCoordinator
    def self.update_after_batch : Bool
      request_target_reached?
    end

    def self.finish
      # Print a final progress line so short runs (< progress interval) still
      # show one, then the report.
      Logger.log_progress
      Logger.log_final
      exit Cryload.stats.final_exit_code
    end

    private def self.request_target_reached? : Bool
      return false if Cryload.stats.duration_mode

      target = Cryload.stats.request_number
      return false unless target > 0

      Cryload.stats.total_request_count >= target.to_i64
    end
  end
end
