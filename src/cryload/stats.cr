module Cryload
  # Stats holder for the benchmark
  class Stats
    getter :total_request_count

    def initialize
      @total_request_count = 0
      @request_times = [] of Float64
    end

    def increase_total_request_count()
      @total_request_count+=1
    end

    def add_to_request_times(time)
      @request_times << time
    end

    def average_request_time
      total_request_time = @request_times.sum
      total_request_time / total_request_count
    end

    def request_per_second
      1000 / average_request_time
    end
  end
end
