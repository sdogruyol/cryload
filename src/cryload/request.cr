module Cryload
  class Request
    getter :time_taken

    def initialize(start_time, end_time)
      @time_taken = (end_time - start_time).to_f * 1000.0
    end

  end
end
