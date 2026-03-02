module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32)
      puts "Running load test @ #{url}"
      puts
    end

    # Logs the final stats
    def self.log_final
      s = Cryload.stats
      return if s.empty?

      avg_ms = s.average_request_time.round(2)
      stdev_ms = s.latency_stdev.round(2)
      max_ms = s.max_request_time.round(2)
      rps = s.request_per_second.round(2)
      total = s.total_request_count
      elapsed = s.wall_clock_seconds.round(2)

      puts "  Stats      Avg      Stdev    Max"
      puts "  Latency    #{avg_ms}ms   #{stdev_ms}ms   #{max_ms}ms"
      puts
      puts "  #{total} requests in #{elapsed}s"
      puts "  Requests/sec:  #{rps}"
      puts "  2xx: #{s.ok_requests}    Non-2xx: #{s.not_ok_requests}"
    end
  end
end
