require "csv"

module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32, rate_limit : Int32?)
      return unless Cryload.stats.output_format == "text"

      mode = if duration_sec
               "duration (#{duration_sec}s)"
             else
               "request-count (#{request_count || 0} requests)"
             end

      puts "Running load test @ #{url}"
      puts "Mode: #{mode}"
      puts "Connections: #{connections}"
      puts "Rate limit: #{rate_limit ? "#{rate_limit} req/s" : "unlimited"}"
      puts "Success statuses: #{format_success_statuses(Cryload.stats.success_status_ranges)}"
      puts
    end

    # Logs the final stats
    def self.log_final
      s = Cryload.stats

      avg_ms = s.average_request_time.round(2)
      min_ms = s.min_request_time.round(2)
      stdev_ms = s.latency_stdev.round(2)
      max_ms = s.max_request_time.round(2)
      p50_ms = s.p50_request_time.round(2)
      p25_ms = s.p25_request_time.round(2)
      p90_ms = s.p90_request_time.round(2)
      p95_ms = s.p95_request_time.round(2)
      p99_ms = s.p99_request_time.round(2)
      p999_ms = s.p999_request_time.round(2)
      p10_ms = s.p10_request_time.round(2)
      p75_ms = s.p75_request_time.round(2)
      rps = s.request_per_second.round(2)
      total = s.total_request_count
      elapsed = s.wall_clock_seconds.round(2)
      error_count = s.transport_error_count
      response_count = s.response_count
      total_response_bytes = s.total_response_bytes
      average_bytes_per_response = s.average_bytes_per_response
      bytes_per_second = s.bytes_per_second
      success_percent = percentage(s.ok_requests, response_count)
      failure_percent = percentage(s.not_ok_requests, response_count)
      transport_error_percent = percentage(error_count, total)
      exact_status_counts = s.status_code_counts
      error_counts = s.error_counts
      histogram_bins = s.latency_histogram_bins
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
          "transfer"            => {
            "total_bytes"            => total_response_bytes,
            "size_per_request_bytes" => average_bytes_per_response.round(2),
            "bytes_per_second"       => bytes_per_second.round(2),
          },
          "latency_ms" => {
            "min"   => min_ms,
            "p50"   => p50_ms,
            "p25"   => p25_ms,
            "p90"   => p90_ms,
            "avg"   => avg_ms,
            "stdev" => stdev_ms,
            "max"   => max_ms,
            "p95"   => p95_ms,
            "p99"   => p99_ms,
            "p999"  => p999_ms,
            "p10"   => p10_ms,
            "p75"   => p75_ms,
          },
          "latency_distribution_ms" => {
            "p10"  => p10_ms,
            "p25"  => p25_ms,
            "p50"  => p50_ms,
            "p75"  => p75_ms,
            "p90"  => p90_ms,
            "p95"  => p95_ms,
            "p99"  => p99_ms,
            "p999" => p999_ms,
          },
          "latency_histogram" => histogram_bins.map do |bin|
            {
              "start_ms" => bin[:start_ms],
              "end_ms"   => bin[:end_ms],
              "count"    => bin[:count],
              "percent"  => bin[:percent],
            }
          end,
          "status_counts" => {
            "successful"         => s.ok_requests,
            "successful_percent" => success_percent,
            "failed"             => s.not_ok_requests,
            "failed_percent"     => failure_percent,
          },
          "success_statuses"        => success_status_ranges,
          "response_status_codes"   => exact_status_counts.transform_keys(&.to_s),
          "error_counts"            => error_counts,
          "transport_error_percent" => transport_error_percent,
        }
        puts payload.to_json
        return
      end

      if s.csv_output
        print_csv total, response_count, error_count, elapsed, rps, total_response_bytes, average_bytes_per_response, bytes_per_second, avg_ms, min_ms, stdev_ms, max_ms, p50_ms, p90_ms, p95_ms, p99_ms, p999_ms, s.ok_requests, s.not_ok_requests, success_percent, failure_percent, transport_error_percent, success_status_ranges, exact_status_counts, error_counts
        return
      end

      return if s.quiet_output

      puts "Summary"
      puts "  Total requests: #{total}"
      puts "  Total time: #{elapsed}s"
      puts "  Requests/sec: #{rps}"
      puts "  Responses: #{response_count}"
      puts "  Transport errors: #{error_count} (#{transport_error_percent}%)"
      puts
      puts "Transfer"
      puts "  Total data: #{format_bytes(total_response_bytes)}"
      puts "  Size/request: #{format_bytes(average_bytes_per_response)}"
      puts "  Transfer/sec: #{format_bytes(bytes_per_second)}/s"
      puts
      puts "Latency (ms)"
      puts "  avg: #{avg_ms}   min: #{min_ms}   stdev: #{stdev_ms}   max: #{max_ms}"
      puts
      puts "Percentiles (ms)"
      puts "  p50: #{p50_ms}   p90: #{p90_ms}   p95: #{p95_ms}"
      puts "  p99: #{p99_ms}   p999: #{p999_ms}"
      puts
      puts "Response Time Histogram (ms)"
      print_histogram histogram_bins
      puts
      puts "Response Time Distribution (ms)"
      puts "  10.0% in #{p10_ms}"
      puts "  25.0% in #{p25_ms}"
      puts "  50.0% in #{p50_ms}"
      puts "  75.0% in #{p75_ms}"
      puts "  90.0% in #{p90_ms}"
      puts "  95.0% in #{p95_ms}"
      puts "  99.0% in #{p99_ms}"
      puts "  99.9% in #{p999_ms}"
      puts
      puts "Status Summary"
      puts "  Successful: #{s.ok_requests} (#{success_percent}%)"
      puts "  Failed: #{s.not_ok_requests} (#{failure_percent}%)"
      puts "  Success statuses: #{success_status_ranges.join(", ")}"
      unless exact_status_counts.empty?
        details = exact_status_counts.keys.sort.map { |status| "#{status}: #{exact_status_counts[status]}" }.join("  ")
        puts "  Status codes: #{details}"
      end
      unless error_counts.empty?
        details = error_counts.keys.sort.map { |category| "#{category}: #{error_counts[category]}" }.join("  ")
        puts "  Error details: #{details}"
      end
    end

    private def self.print_csv(total, response_count, error_count, elapsed, rps, total_response_bytes, average_bytes_per_response, bytes_per_second, avg_ms, min_ms, stdev_ms, max_ms, p50_ms, p90_ms, p95_ms, p99_ms, p999_ms, successful_count, failed_count, successful_percent, failed_percent, transport_error_percent, success_status_ranges, exact_status_counts, error_counts)
      headers = [
        "url",
        "duration_mode",
        "requests",
        "responses",
        "transport_errors",
        "elapsed_seconds",
        "requests_per_second",
        "total_response_bytes",
        "size_per_request_bytes",
        "bytes_per_second",
        "latency_avg_ms",
        "latency_min_ms",
        "latency_stdev_ms",
        "latency_max_ms",
        "latency_p50_ms",
        "latency_p90_ms",
        "latency_p95_ms",
        "latency_p99_ms",
        "latency_p999_ms",
        "successful",
        "successful_percent",
        "failed",
        "failed_percent",
        "transport_error_percent",
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
        total_response_bytes.to_s,
        average_bytes_per_response.round(2).to_s,
        bytes_per_second.round(2).to_s,
        avg_ms.to_s,
        min_ms.to_s,
        stdev_ms.to_s,
        max_ms.to_s,
        p50_ms.to_s,
        p90_ms.to_s,
        p95_ms.to_s,
        p99_ms.to_s,
        p999_ms.to_s,
        successful_count.to_s,
        successful_percent.to_s,
        failed_count.to_s,
        failed_percent.to_s,
        transport_error_percent.to_s,
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

    private def self.percentage(count : Int64, total : Int64)
      return 0.0 if total == 0
      ((count.to_f / total) * 100.0).round(2)
    end

    private def self.format_bytes(bytes : Int | Int64 | Float64)
      value = bytes.to_f
      return "0 B" if value <= 0

      units = {"B", "KiB", "MiB", "GiB"}
      unit_index = 0
      while value >= 1024.0 && unit_index < units.size - 1
        value /= 1024.0
        unit_index += 1
      end

      "#{value.round(2)} #{units[unit_index]}"
    end

    private def self.print_histogram(histogram_bins)
      max_count = histogram_bins.max_of? { |bin| bin[:count] } || 0_i64

      histogram_bins.each do |bin|
        width = max_count > 0 ? ((bin[:count].to_f / max_count) * 32).round.to_i : 0
        width = 1 if bin[:count] > 0 && width == 0
        bar = "■" * width
        label = bin[:end_ms].round(2)
        puts "  #{label} [#{bin[:count]}] |#{bar}"
      end
    end

    private def self.format_success_statuses(status_ranges : Array(Range(Int32, Int32)))
      status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end.join(", ")
    end
  end
end
