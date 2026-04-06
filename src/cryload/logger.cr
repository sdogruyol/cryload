module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32, rate_limit : Int32?)
      return if Cryload.stats.json_output
      puts "Running load test @ #{url}"
      puts "Rate limit: #{rate_limit} req/s" if rate_limit
      puts
    end

    # Logs the final stats
    def self.log_final
      s = Cryload.stats
      return if s.empty?

      avg_ms = s.average_request_time.round(2)
      stdev_ms = s.latency_stdev.round(2)
      max_ms = s.max_request_time.round(2)
      p50_ms = s.p50_request_time.round(2)
      p90_ms = s.p90_request_time.round(2)
      p95_ms = s.p95_request_time.round(2)
      p99_ms = s.p99_request_time.round(2)
      p999_ms = s.p999_request_time.round(2)
      rps = s.request_per_second.round(2)
      total = s.total_request_count
      elapsed = s.wall_clock_seconds.round(2)
      error_count = s.transport_error_count
      response_count = s.response_count
      exact_status_counts = s.status_code_counts
      error_counts = s.error_counts

      if s.json_output
        payload = {
          "url"                 => s.url,
          "duration_mode"       => s.duration_mode,
          "requests"            => total,
          "responses"           => response_count,
          "transport_errors"    => error_count,
          "elapsed_seconds"     => elapsed,
          "requests_per_second" => rps,
          "latency_ms"          => {
            "p50"   => p50_ms,
            "p90"   => p90_ms,
            "avg"   => avg_ms,
            "stdev" => stdev_ms,
            "max"   => max_ms,
            "p95"   => p95_ms,
            "p99"   => p99_ms,
            "p999"  => p999_ms,
          },
          "status_counts" => {
            "2xx"     => s.ok_requests,
            "non_2xx" => s.not_ok_requests,
          },
          "response_status_codes" => exact_status_counts.transform_keys(&.to_s),
          "error_counts"          => error_counts,
        }
        puts payload.to_json
        return
      end

      puts "  Latency (ms)      avg: #{avg_ms}   stdev: #{stdev_ms}   max: #{max_ms}"
      puts
      puts "  Percentiles (ms)  p50: #{p50_ms}   p90: #{p90_ms}   p95: #{p95_ms}"
      puts "                    p99: #{p99_ms}   p999: #{p999_ms}"
      puts
      puts "#{total} requests in #{elapsed}s"
      puts "Requests/sec:  #{rps}"
      puts "Responses: #{response_count}    Errors: #{error_count}"
      puts "2xx: #{s.ok_requests}    Non-2xx: #{s.not_ok_requests}"
      unless exact_status_counts.empty?
        details = exact_status_counts.keys.sort.map { |status| "#{status}: #{exact_status_counts[status]}" }.join("  ")
        puts "Status codes: #{details}"
      end
      unless error_counts.empty?
        details = error_counts.keys.sort.map { |category| "#{category}: #{error_counts[category]}" }.join("  ")
        puts "Transport errors: #{details}"
      end
    end
  end
end
