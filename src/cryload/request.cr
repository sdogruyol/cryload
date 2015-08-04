module Cryload
  class Request
    getter :time_taken

    def initialize(start_time, end_time, @status_code)
      @time_taken = (end_time - start_time).to_f * 1000.0
    end

    def is_ok?
      @status_code.between?(200, 300)
    end

  end
end
