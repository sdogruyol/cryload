require "csv"

module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32, rate_limit : Int32?)
      return unless Cryload.stats.output_format == "text"
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
      success_status_ranges = s.success_status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end

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
            "successful" => s.ok_requests,
            "failed"     => s.not_ok_requests,
          },
          "success_statuses"      => success_status_ranges,
          "response_status_codes" => exact_status_counts.transform_keys(&.to_s),
          "error_counts"          => error_counts,
        }
        puts payload.to_json
        return
      end

      if s.csv_output
        print_csv total, response_count, error_count, elapsed, rps, avg_ms, stdev_ms, max_ms, p50_ms, p90_ms, p95_ms, p99_ms, p999_ms, s.ok_requests, s.not_ok_requests, success_status_ranges, exact_status_counts, error_counts
        return
      end

      return if s.quiet_output

      puts "  Latency (ms)      avg: #{avg_ms}   stdev: #{stdev_ms}   max: #{max_ms}"
      puts
      puts "  Percentiles (ms)  p50: #{p50_ms}   p90: #{p90_ms}   p95: #{p95_ms}"
      puts "                    p99: #{p99_ms}   p999: #{p999_ms}"
      puts
      puts "#{total} requests in #{elapsed}s"
      puts "Requests/sec:  #{rps}"
      puts "Responses: #{response_count}    Errors: #{error_count}"
      puts "Successful: #{s.ok_requests}    Failed: #{s.not_ok_requests}"
      puts "Success statuses: #{success_status_ranges.join(", ")}"
      unless exact_status_counts.empty?
        details = exact_status_counts.keys.sort.map { |status| "#{status}: #{exact_status_counts[status]}" }.join("  ")
        puts "Status codes: #{details}"
      end
      unless error_counts.empty?
        details = error_counts.keys.sort.map { |category| "#{category}: #{error_counts[category]}" }.join("  ")
        puts "Transport errors: #{details}"
      end
    end

    private def self.print_csv(total, response_count, error_count, elapsed, rps, avg_ms, stdev_ms, max_ms, p50_ms, p90_ms, p95_ms, p99_ms, p999_ms, successful_count, failed_count, success_status_ranges, exact_status_counts, error_counts)
      headers = [
        "url",
        "duration_mode",
        "requests",
        "responses",
        "transport_errors",
        "elapsed_seconds",
        "requests_per_second",
        "latency_avg_ms",
        "latency_stdev_ms",
        "latency_max_ms",
        "latency_p50_ms",
        "latency_p90_ms",
        "latency_p95_ms",
        "latency_p99_ms",
        "latency_p999_ms",
        "successful",
        "failed",
        "success_statuses",
        "response_status_codes",
        "error_counts",
      ]
      success_statuses = success_status_ranges.join(";")
      status_codes = exact_status_counts.keys.sort.map { |status| "#{status}:#{exact_status_counts[status]}" }.join(";")
      errors = error_counts.keys.sort.map { |category| "#{category}:#{error_counts[category]}" }.join(";")
      row = [
        Cryload.stats.url,
        Cryload.stats.duration_mode.to_s,
        total.to_s,
        response_count.to_s,
        error_count.to_s,
        elapsed.to_s,
        rps.to_s,
        avg_ms.to_s,
        stdev_ms.to_s,
        max_ms.to_s,
        p50_ms.to_s,
        p90_ms.to_s,
        p95_ms.to_s,
        p99_ms.to_s,
        p999_ms.to_s,
        successful_count.to_s,
        failed_count.to_s,
        success_statuses,
        status_codes,
        errors,
      ]
      csv_output = CSV.build do |csv|
        csv.row headers
        csv.row row
      end
      puts csv_output
    end
  end
end
