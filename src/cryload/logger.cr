require "csv"

module Cryload
  # Singleton class which handles all the logging
  class Logger
    # Logs the test header
    def self.log_header(url : String, duration_sec : Int32?, request_count : Int32?, connections : Int32, rate_limit : Int32?, warmup_seconds : Int32 = 0, disable_keepalive : Bool = false)
      return unless Cryload.stats.output_format == "text"

      mode = if duration_sec
               "duration (#{duration_sec}s)"
             else
               "request-count (#{request_count || 0} requests)"
             end

      puts "Running load test @ #{url}"
      puts "Mode: #{mode}"
      puts "Connections: #{connections}"
      puts "Keep-alive: #{disable_keepalive ? "disabled" : "enabled"}"
      puts "Rate limit: #{rate_limit ? "#{rate_limit} req/s" : "unlimited"}"
      puts "Warmup: #{warmup_seconds > 0 ? "#{warmup_seconds}s" : "none"}"
      puts "Success statuses: #{format_success_statuses(Cryload.stats.success_status_ranges)}"
      puts
    end

    def self.log_warmup(seconds : Int32)
      return unless Cryload.stats.text_output?
      puts "Warming up for #{seconds}s...".colorize(:yellow)
    end

    def self.log_progress
      return unless Cryload.stats.progress_enabled
      return unless Cryload.stats.text_output?

      stats = Cryload.stats
      count = stats.total_request_count
      rps = stats.request_per_second.round(0)
      STDERR.print "\r  Progress: #{count} requests, #{rps} req/s"
    end

    # Logs the final stats
    def self.log_final
      STDERR.puts if Cryload.stats.progress_enabled && Cryload.stats.text_output?
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
      status_distribution = build_status_distribution exact_status_counts, response_count
      transport_error_distribution = build_error_distribution error_counts, error_count
      success_status_ranges = s.success_status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end

      if s.json_output
        puts json_document(s)
        return
      end

      if s.csv_output
        puts csv_document(s)
        return
      end

      return if s.quiet_output

      puts "Summary"
      puts "  Total requests: #{total}"
      puts "  Total time: #{elapsed}s"
      puts "  Requests/sec: #{rps}"
      puts "  Responses: #{response_count}"
      puts "  Transport errors: #{error_count} (#{transport_error_percent}%)"
      puts "  Fastest: #{min_ms} ms"
      puts "  Slowest: #{max_ms} ms"
      puts
      puts "Status"
      puts "  Successful: #{s.ok_requests} (#{success_percent}%)"
      puts "  Failed: #{s.not_ok_requests} (#{failure_percent}%)"
      puts "  Success statuses: #{success_status_ranges.join(", ")}"
      puts
      puts "Transfer"
      puts "  Total data: #{format_bytes(total_response_bytes)}"
      puts "  Size/request: #{format_bytes(average_bytes_per_response)}"
      puts "  Transfer/sec: #{format_bytes(bytes_per_second)}/s"
      puts
      puts "Latency (ms)"
      puts "  avg: #{format_latency_value(avg_ms)}   min: #{format_latency_value(min_ms)}   stdev: #{format_latency_value(stdev_ms)}   max: #{format_latency_value(max_ms)}"
      puts
      puts "Latency Percentiles (ms)"
      puts "  p50: #{format_latency_value(p50_ms)}   p90: #{format_latency_value(p90_ms)}   p95: #{format_latency_value(p95_ms)}"
      puts "  p99: #{format_latency_value(p99_ms)}   p999: #{format_latency_value(p999_ms)}"
      puts
      puts "Latency Histogram (ms)"
      print_histogram histogram_bins
      puts
      puts "Latency Distribution (ms)"
      puts "  10.0% in #{format_latency_value(p10_ms)}"
      puts "  25.0% in #{format_latency_value(p25_ms)}"
      puts "  50.0% in #{format_latency_value(p50_ms)}"
      puts "  75.0% in #{format_latency_value(p75_ms)}"
      puts "  90.0% in #{format_latency_value(p90_ms)}"
      puts "  95.0% in #{format_latency_value(p95_ms)}"
      puts "  99.0% in #{format_latency_value(p99_ms)}"
      puts "  99.9% in #{format_latency_value(p999_ms)}"
      puts
      unless status_distribution.empty?
        puts
        puts "Status Code Distribution"
        status_distribution.each do |entry|
          puts "  [#{entry[:label]}] #{entry[:count]} responses (#{entry[:percent]}%)"
        end
      end
      unless transport_error_distribution.empty?
        puts
        puts "Error Distribution"
        transport_error_distribution.each do |entry|
          puts "  [#{entry[:label]}] #{entry[:count]} errors (#{entry[:percent]}%)"
        end
      end
    end

    def self.json_document(s : Stats) : String
      metrics = report_metrics(s)
      build_json_payload(
        s, metrics.total, metrics.response_count, metrics.error_count, metrics.elapsed, metrics.rps,
        metrics.total_response_bytes, metrics.average_bytes_per_response, metrics.bytes_per_second,
        metrics.avg_ms, metrics.min_ms, metrics.stdev_ms, metrics.max_ms,
        metrics.p10_ms, metrics.p25_ms, metrics.p50_ms, metrics.p75_ms, metrics.p90_ms, metrics.p95_ms,
        metrics.p99_ms, metrics.p999_ms, metrics.success_percent, metrics.failure_percent,
        metrics.transport_error_percent, metrics.success_status_ranges, metrics.status_distribution,
        metrics.transport_error_distribution, metrics.histogram_bins
      ).to_json
    end

    def self.csv_document(s : Stats) : String
      metrics = report_metrics(s)
      format_csv(
        metrics.total, metrics.response_count, metrics.error_count, metrics.elapsed, metrics.rps,
        metrics.total_response_bytes, metrics.average_bytes_per_response, metrics.bytes_per_second,
        metrics.avg_ms, metrics.min_ms, metrics.stdev_ms, metrics.max_ms,
        metrics.p50_ms, metrics.p90_ms, metrics.p95_ms, metrics.p99_ms, metrics.p999_ms,
        s.ok_requests, s.not_ok_requests, metrics.success_percent, metrics.failure_percent,
        metrics.transport_error_percent, metrics.success_status_ranges, metrics.status_distribution,
        metrics.transport_error_distribution, s.url, s.duration_mode
      )
    end

    private struct ReportMetrics
      @total : Int64
      @response_count : Int64
      @error_count : Int64
      @elapsed : Float64
      @rps : Float64
      @total_response_bytes : Int64
      @average_bytes_per_response : Float64
      @bytes_per_second : Float64
      @avg_ms : Float64
      @min_ms : Float64
      @stdev_ms : Float64
      @max_ms : Float64
      @p10_ms : Float64
      @p25_ms : Float64
      @p50_ms : Float64
      @p75_ms : Float64
      @p90_ms : Float64
      @p95_ms : Float64
      @p99_ms : Float64
      @p999_ms : Float64
      @success_percent : Float64
      @failure_percent : Float64
      @transport_error_percent : Float64
      @success_status_ranges : Array(String)
      @status_distribution : Array(NamedTuple(label: String, count: Int64, percent: Float64))
      @transport_error_distribution : Array(NamedTuple(label: String, count: Int64, percent: Float64))
      @histogram_bins : Array(NamedTuple(start_ms: Float64, end_ms: Float64, count: Int64, percent: Float64))

      getter total, response_count, error_count, elapsed, rps
      getter total_response_bytes, average_bytes_per_response, bytes_per_second
      getter avg_ms, min_ms, stdev_ms, max_ms
      getter p10_ms, p25_ms, p50_ms, p75_ms, p90_ms, p95_ms, p99_ms, p999_ms
      getter success_percent, failure_percent, transport_error_percent
      getter success_status_ranges, status_distribution, transport_error_distribution, histogram_bins

      def initialize(
        @total : Int64,
        @response_count : Int64,
        @error_count : Int64,
        @elapsed : Float64,
        @rps : Float64,
        @total_response_bytes : Int64,
        @average_bytes_per_response : Float64,
        @bytes_per_second : Float64,
        @avg_ms : Float64,
        @min_ms : Float64,
        @stdev_ms : Float64,
        @max_ms : Float64,
        @p10_ms : Float64,
        @p25_ms : Float64,
        @p50_ms : Float64,
        @p75_ms : Float64,
        @p90_ms : Float64,
        @p95_ms : Float64,
        @p99_ms : Float64,
        @p999_ms : Float64,
        @success_percent : Float64,
        @failure_percent : Float64,
        @transport_error_percent : Float64,
        @success_status_ranges : Array(String),
        @status_distribution : Array(NamedTuple(label: String, count: Int64, percent: Float64)),
        @transport_error_distribution : Array(NamedTuple(label: String, count: Int64, percent: Float64)),
        @histogram_bins : Array(NamedTuple(start_ms: Float64, end_ms: Float64, count: Int64, percent: Float64)),
      )
      end
    end

    private def self.report_metrics(s : Stats) : ReportMetrics
      total = s.total_request_count
      response_count = s.response_count
      error_count = s.transport_error_count
      success_status_ranges = s.success_status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end
      status_distribution = build_status_distribution s.status_code_counts, response_count
      transport_error_distribution = build_error_distribution s.error_counts, error_count

      ReportMetrics.new(
        total,
        response_count,
        error_count,
        s.wall_clock_seconds.round(2),
        s.request_per_second.round(2),
        s.total_response_bytes,
        s.average_bytes_per_response,
        s.bytes_per_second,
        s.average_request_time.round(2),
        s.min_request_time.round(2),
        s.latency_stdev.round(2),
        s.max_request_time.round(2),
        s.p10_request_time.round(2),
        s.p25_request_time.round(2),
        s.p50_request_time.round(2),
        s.p75_request_time.round(2),
        s.p90_request_time.round(2),
        s.p95_request_time.round(2),
        s.p99_request_time.round(2),
        s.p999_request_time.round(2),
        percentage(s.ok_requests, response_count),
        percentage(s.not_ok_requests, response_count),
        percentage(error_count, total),
        success_status_ranges,
        status_distribution,
        transport_error_distribution,
        s.latency_histogram_bins,
      )
    end

    private def self.build_json_payload(
      s, total, response_count, error_count, elapsed, rps, total_response_bytes,
      average_bytes_per_response, bytes_per_second, avg_ms, min_ms, stdev_ms, max_ms,
      p10_ms, p25_ms, p50_ms, p75_ms, p90_ms, p95_ms, p99_ms, p999_ms, success_percent, failure_percent,
      transport_error_percent, success_status_ranges, status_distribution, transport_error_distribution,
      histogram_bins,
    )
      {
        "url"           => s.url,
        "duration_mode" => s.duration_mode,
        "summary"       => {
          "requests"             => total,
          "responses"            => response_count,
          "transport_errors"     => error_count,
          "elapsed_seconds"      => elapsed,
          "requests_per_second"  => rps,
          "failure_rate_percent" => s.failure_rate_percent.round(2),
        },
        "transfer" => {
          "total_bytes"            => total_response_bytes,
          "size_per_request_bytes" => average_bytes_per_response.round(2),
          "bytes_per_second"       => bytes_per_second.round(2),
        },
        "latency_ms" => {
          "avg"   => avg_ms,
          "min"   => min_ms,
          "max"   => max_ms,
          "stdev" => stdev_ms,
          "p10"   => p10_ms,
          "p25"   => p25_ms,
          "p50"   => p50_ms,
          "p75"   => p75_ms,
          "p90"   => p90_ms,
          "p95"   => p95_ms,
          "p99"   => p99_ms,
          "p999"  => p999_ms,
        },
        "latency_histogram" => histogram_bins.map do |bin|
          {
            "start_ms" => bin[:start_ms],
            "end_ms"   => bin[:end_ms],
            "count"    => bin[:count],
            "percent"  => bin[:percent],
          }
        end,
        "status" => {
          "success_statuses"        => success_status_ranges,
          "successful_count"        => s.ok_requests,
          "successful_percent"      => success_percent,
          "failed_count"            => s.not_ok_requests,
          "failed_percent"          => failure_percent,
          "transport_error_percent" => transport_error_percent,
          "codes"                   => status_distribution.map do |entry|
            {
              "code"    => entry[:label],
              "count"   => entry[:count],
              "percent" => entry[:percent],
            }
          end,
          "transport_errors" => transport_error_distribution.map do |entry|
            {
              "category" => entry[:label],
              "count"    => entry[:count],
              "percent"  => entry[:percent],
            }
          end,
        },
      }
    end

    private def self.format_csv(
      total, response_count, error_count, elapsed, rps, total_response_bytes,
      average_bytes_per_response, bytes_per_second, avg_ms, min_ms, stdev_ms, max_ms,
      p50_ms, p90_ms, p95_ms, p99_ms, p999_ms, successful_count, failed_count,
      successful_percent, failed_percent, transport_error_percent, success_status_ranges,
      status_distribution, transport_error_distribution, url : String, duration_mode : Bool,
    )
      headers = [
        "url",
        "duration_mode",
        "requests",
        "responses",
        "transport_errors",
        "elapsed_seconds",
        "requests_per_second",
        "transfer_total_bytes",
        "transfer_size_per_request_bytes",
        "transfer_bytes_per_second",
        "latency_avg_ms",
        "latency_fastest_ms",
        "latency_min_ms",
        "latency_stdev_ms",
        "latency_slowest_ms",
        "latency_max_ms",
        "latency_p50_ms",
        "latency_p90_ms",
        "latency_p95_ms",
        "latency_p99_ms",
        "latency_p999_ms",
        "status_successful_count",
        "status_successful_percent",
        "status_failed_count",
        "status_failed_percent",
        "transport_error_percent",
        "status_successes",
        "status_code_distribution",
        "transport_error_distribution",
      ]
      success_statuses = success_status_ranges.join(";")
      status_codes = status_distribution.map { |entry| "#{entry[:label]}:#{entry[:count]}:#{entry[:percent]}%" }.join(";")
      errors = transport_error_distribution.map { |entry| "#{entry[:label]}:#{entry[:count]}:#{entry[:percent]}%" }.join(";")
      row = [
        url,
        duration_mode.to_s,
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
        min_ms.to_s,
        stdev_ms.to_s,
        max_ms.to_s,
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
      CSV.build do |csv|
        csv.row headers
        csv.row row
      end
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
      max_label_width = histogram_bins.max_of? { |bin| histogram_label(bin).size } || 0

      histogram_bins.each do |bin|
        width = max_count > 0 ? ((bin[:count].to_f / max_count) * 32).round.to_i : 0
        width = 1 if bin[:count] > 0 && width == 0
        bar = "■" * width
        label = histogram_label(bin).rjust(max_label_width)
        puts "  #{label} [#{bin[:count]}] |#{bar}"
      end
    end

    private def self.format_success_statuses(status_ranges : Array(Range(Int32, Int32)))
      status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end.join(", ")
    end

    private def self.histogram_label(bin)
      "#{format_latency_value(bin[:end_ms])} ms"
    end

    private def self.format_latency_value(value : Float64)
      if value < 10.0
        value.round(3).to_s
      elsif value < 100.0
        value.round(2).to_s
      else
        value.round(1).to_s
      end
    end

    private def self.build_status_distribution(status_counts : Hash(Int32, Int64), total_responses : Int64)
      status_counts
        .map do |status_code, count|
          {
            label:   status_code.to_s,
            count:   count,
            percent: percentage(count, total_responses),
          }
        end
        .sort_by! { |entry| {-entry[:count], entry[:label].to_i} }
    end

    private def self.build_error_distribution(error_counts : Hash(String, Int64), total_errors : Int64)
      error_counts
        .map do |category, count|
          {
            label:   category,
            count:   count,
            percent: percentage(count, total_errors),
          }
        end
        .sort_by! { |entry| {-entry[:count], entry[:label]} }
    end
  end
end
