module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32)
      return if Cryload.stats.json_output
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
      p95_ms = s.p95_request_time.round(2)
      p99_ms = s.p99_request_time.round(2)
      rps = s.request_per_second.round(2)
      total = s.total_request_count
      elapsed = s.wall_clock_seconds.round(2)

      if s.json_output
        payload = {
          "url" => s.url,
          "duration_mode" => s.duration_mode,
          "requests" => total,
          "elapsed_seconds" => elapsed,
          "requests_per_second" => rps,
          "latency_ms" => {
            "avg" => avg_ms,
            "stdev" => stdev_ms,
            "max" => max_ms,
            "p95" => p95_ms,
            "p99" => p99_ms,
          },
          "status_counts" => {
            "2xx" => s.ok_requests,
            "non_2xx" => s.not_ok_requests,
          },
        }
        puts payload.to_json
        return
      end

      puts "  Latency (ms)      avg: #{avg_ms}   stdev: #{stdev_ms}   max: #{max_ms}"
      puts
      puts "  Percentiles (ms)  p95: #{p95_ms}   p99: #{p99_ms}"
      puts
      puts "#{total} requests in #{elapsed}s"
      puts "Requests/sec:  #{rps}"
      puts "2xx: #{s.ok_requests}    Non-2xx: #{s.not_ok_requests}"
    end
  end
end
