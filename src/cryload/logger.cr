require "csv"

module Cryload
  # Singleton class which handles all the logging
  class Logger
    SCHEMA_VERSION = 1

    # Under multiple worker threads the progress ticker, the one-shot connection
    # diagnostic and the final report can all reach stderr at once; without a
    # lock they interleave mid-line.
    @@stderr_mutex = Mutex.new

    def self.abort_with_config_error(message : String) : NoReturn
      STDERR.puts message.colorize(:red)
      exit ExitCode::ConfigError.value
    end

    # Logs the test header
    def self.log_header(url : String, fiber_count : Int32)
      stats = Cryload.stats
      return unless stats.text_output?
      config = stats.config

      mode = if duration = config.duration
               "duration (#{Duration.format(duration)})"
             else
               "request-count (#{config.request_number || 0} requests)"
             end

      puts "Running load test @ #{url}"
      puts "Mode: #{mode}"
      puts "Connections: #{fiber_count}"
      puts "Workers: #{config.workers}"
      puts "Keep-alive: #{config.keepalive? ? "enabled" : "disabled"}"
      puts "Rate limit: #{config.rate_limit.try { |rate| "#{format_rate(rate)} req/s" } || "unlimited"}"
      puts "Latency correction: #{config.latency_correction? ? "on" : "off"}"
      puts "Timeout: #{format_span(config.timeout)}"
      puts "Request timeout: #{format_span(config.request_timeout)}"
      puts "Warmup: #{format_span(config.warmup)}"
      puts "Success statuses: #{format_success_statuses(Cryload.stats.success_status_ranges)}"
      puts
    end

    def self.log_warmup(warmup : Time::Span)
      return unless Cryload.stats.text_output?
      puts "Warming up for #{Duration.format(warmup)}...".colorize(:yellow)
    end

    def self.log_connection_error(uri : URI, ex : Exception)
      host = uri.host || "localhost"
      port = Cryload.effective_port(uri)
      @@stderr_mutex.synchronize do
        STDERR.puts "Connection failed: Could not reach #{host}:#{port}"
        STDERR.puts "  → #{ex.message}"
        STDERR.puts "  → Continuing and counting transport errors in the final report."
      end
    end

    def self.log_progress
      stats = Cryload.stats?
      return unless stats
      return unless stats.progress_enabled? && stats.text_output?

      count = stats.total_request_count
      rps = stats.request_per_second.round(0)
      @@stderr_mutex.synchronize do
        STDERR.print "\r  Progress: #{count} requests, #{rps} req/s"
      end
    end

    # Logs the final stats. `signal_code` is set when the run was cut short by a
    # signal, so the verdict says why instead of claiming a clean finish.
    # Returns the exit code the report announced, so the process exits with
    # exactly the verdict it printed rather than re-evaluating the gates.
    def self.log_final(signal_code : ExitCode? = nil) : ExitCode?
      stats = Cryload.stats?
      return unless stats

      if stats.progress_enabled? && stats.text_output?
        @@stderr_mutex.synchronize { STDERR.puts }
      end

      report = Report.new(stats, signal_code)

      if stats.json_output?
        puts report.to_json
      elsif stats.csv_output?
        puts report.to_csv
      elsif !stats.quiet_output?
        report.print_text
      end

      report.exit_code
    end

    # A single consistent snapshot of the run. Every number in one report comes
    # from the same set of reads, so the text, JSON and CSV renderings cannot
    # disagree with each other.
    class Report
      getter stats : Stats
      getter latency : Stats::LatencyView
      getter corrected : Stats::LatencyView
      getter send_delay : Stats::LatencyView
      getter phases : Hash(String, Stats::LatencyView)
      getter rate : Stats::RateReport
      getter thresholds : Array(ThresholdResult)
      getter exit_code : ExitCode

      @signal_code : ExitCode?
      @total : Int64
      @responses : Int64
      @errors : Int64
      @ok : Int64
      @failed : Int64
      @elapsed : Float64
      @rps : Float64
      @total_bytes : Int64
      @bytes_per_request : Float64
      @bytes_per_second : Float64
      @histogram_bins : Array(Histogram::Bin)
      @status_breakdown : Array(Stats::StatusEntry)
      @error_breakdown : Array(Stats::ErrorEntry)
      @url_breakdown : Array(Stats::UrlEntry)?

      def initialize(@stats : Stats, @signal_code : ExitCode? = nil)
        @total = stats.total_request_count
        @responses = stats.response_count
        @errors = stats.transport_error_count
        @ok = stats.ok_requests
        @failed = stats.not_ok_requests
        @elapsed = stats.wall_clock_seconds.round(2)
        @rps = stats.request_per_second.round(2)
        @total_bytes = stats.total_response_bytes
        @bytes_per_request = stats.average_bytes_per_response
        @bytes_per_second = stats.bytes_per_second
        @latency = stats.latency_view
        @corrected = stats.corrected_latency_view
        @send_delay = stats.send_delay_view
        @phases = stats.phase_views
        @rate = stats.rate_report
        @histogram_bins = stats.latency_histogram_bins
        @status_breakdown = stats.status_breakdown
        @error_breakdown = stats.error_breakdown
        @url_breakdown = stats.url_breakdown
        @thresholds = stats.threshold_results
        @exit_code = resolve_exit_code
      end

      private def resolve_exit_code : ExitCode
        run_code = @stats.exit_code
        signal = @signal_code
        return run_code unless signal
        run_code.threshold_breach? ? run_code : signal
      end

      def thresholds_passed? : Bool
        @thresholds.all?(&.passed?)
      end

      # Compact one-line labels for the CSV column and the text report, where
      # a single string is all there is room for. JSON reports the full objects.
      def breached_labels : Array(String)
        @thresholds.reject(&.passed?).map { |result| threshold_label(result) }
      end

      private def threshold_label(result : ThresholdResult) : String
        scope = result.scope == "global" ? "" : "#{result.scope} "
        "#{scope}#{result.metric}#{result.comparator}#{Logger.trim_number(result.limit)}"
      end

      # JSON ------------------------------------------------------------------

      def to_json : String
        {
          "schema_version"       => SCHEMA_VERSION,
          "cryload_version"      => Cryload::VERSION,
          "url"                  => @stats.url,
          "duration_mode"        => @stats.duration_mode?,
          "config"               => config_payload,
          "summary"              => summary_payload,
          "rate"                 => rate_payload,
          "transfer"             => transfer_payload,
          "latency_ms"           => latency_payload(@latency),
          "corrected_latency_ms" => latency_payload(@corrected),
          "send_delay_ms"        => send_delay_payload,
          "phases_ms"            => phases_payload,
          "latency_histogram"    => histogram_payload,
          "status"               => status_payload,
          "by_status"            => by_status_payload,
          "by_url"               => by_url_payload,
          "thresholds"           => thresholds_payload,
          "verdict"              => {
            "exit_code" => @exit_code.value,
            "reason"    => @exit_code.reason,
          },
        }.to_json
      end

      private def config_payload
        config = @stats.config
        {
          "workers"                 => config.workers,
          "connections"             => config.connections,
          "rate_limit"              => config.rate_limit,
          "latency_correction"      => config.latency_correction?,
          "keepalive"               => config.keepalive?,
          "request_timeout_seconds" => config.request_timeout.try(&.total_seconds),
          "timeout_seconds"         => config.timeout.try(&.total_seconds),
        }
      end

      private def summary_payload
        {
          "requests"             => @total,
          "responses"            => @responses,
          "transport_errors"     => @errors,
          "elapsed_seconds"      => @elapsed,
          "requests_per_second"  => @rps,
          "failure_rate_percent" => @stats.failure_rate_percent.round(2),
        }
      end

      private def rate_payload
        {
          "requested_per_second" => @rate.requested,
          "attained_per_second"  => @rate.attained.round(2),
          "attainment_percent"   => @rate.attainment_percent.try(&.round(2)),
          "scheduled_requests"   => @rate.scheduled_requests,
          "skipped_requests"     => @rate.skipped_requests,
          "schedule_drift_ms"    => @rate.schedule_drift_ms.try(&.round(2)),
        }
      end

      private def transfer_payload
        {
          "total_bytes"            => @total_bytes,
          "size_per_request_bytes" => @bytes_per_request.round(2),
          "bytes_per_second"       => @bytes_per_second.round(2),
        }
      end

      private def latency_payload(view : Stats::LatencyView)
        {
          "avg"   => view.avg.round(2),
          "min"   => view.min.round(2),
          "max"   => view.max.round(2),
          "stdev" => view.stdev.round(2),
          "p10"   => view.p(10.0).round(2),
          "p25"   => view.p(25.0).round(2),
          "p50"   => view.p(50.0).round(2),
          "p75"   => view.p(75.0).round(2),
          "p90"   => view.p(90.0).round(2),
          "p95"   => view.p(95.0).round(2),
          "p99"   => view.p(99.0).round(2),
          "p999"  => view.p(99.9).round(2),
        }
      end

      private def send_delay_payload
        {
          "avg"   => @send_delay.avg.round(2),
          "min"   => @send_delay.min.round(2),
          "max"   => @send_delay.max.round(2),
          "stdev" => @send_delay.stdev.round(2),
          "p50"   => @send_delay.p(50.0).round(2),
          "p90"   => @send_delay.p(90.0).round(2),
          "p99"   => @send_delay.p(99.0).round(2),
          "p999"  => @send_delay.p(99.9).round(2),
        }
      end

      private def phases_payload
        payload = Hash(String, Hash(String, Float64 | Int64)).new
        @phases.each do |name, view|
          payload[name] = {
            "count" => view.count,
            "avg"   => view.avg.round(2),
            "min"   => view.min.round(2),
            "max"   => view.max.round(2),
            "p50"   => view.p(50.0).round(2),
            "p95"   => view.p(95.0).round(2),
            "p99"   => view.p(99.0).round(2),
          } of String => Float64 | Int64
        end
        payload
      end

      private def histogram_payload
        @histogram_bins.map do |bin|
          {
            "start_ms" => bin.start_ms,
            "end_ms"   => bin.end_ms,
            "count"    => bin.count,
            "percent"  => bin.percent,
          }
        end
      end

      private def status_payload
        {
          "success_statuses"        => success_status_ranges,
          "successful_count"        => @ok,
          "successful_percent"      => Logger.percentage(@ok, @responses),
          "failed_count"            => @failed,
          "failed_percent"          => Logger.percentage(@failed, @responses),
          "transport_error_percent" => Logger.percentage(@errors, @total),
          "codes"                   => @status_breakdown.map do |entry|
            {
              "code"    => entry.code.to_s,
              "count"   => entry.count,
              "percent" => entry.percent,
            }
          end,
          "transport_errors" => @error_breakdown.map do |entry|
            {
              "category"       => entry.category,
              "count"          => entry.count,
              "percent"        => entry.percent,
              "sample_message" => entry.sample_message,
            }
          end,
        }
      end

      private def by_status_payload
        @status_breakdown.map do |entry|
          {
            "code"    => entry.code,
            "count"   => entry.count,
            "percent" => entry.percent,
            "avg_ms"  => entry.avg_ms,
            "p50_ms"  => entry.p50_ms,
            "p95_ms"  => entry.p95_ms,
            "p99_ms"  => entry.p99_ms,
          }
        end
      end

      private def by_url_payload
        breakdown = @url_breakdown
        return unless breakdown

        breakdown.map do |entry|
          {
            "url"                  => entry.url,
            "requests"             => entry.requests,
            "responses"            => entry.responses,
            "transport_errors"     => entry.transport_errors,
            "ok"                   => entry.ok,
            "failed"               => entry.failed,
            "failure_rate_percent" => entry.failure_rate_percent,
            "requests_per_second"  => entry.requests_per_second,
            "avg_ms"               => entry.avg_ms,
            "min_ms"               => entry.min_ms,
            "max_ms"               => entry.max_ms,
            "p50_ms"               => entry.p50_ms,
            "p75_ms"               => entry.p75_ms,
            "p90_ms"               => entry.p90_ms,
            "p95_ms"               => entry.p95_ms,
            "p99_ms"               => entry.p99_ms,
            "p999_ms"              => entry.p999_ms,
          }
        end
      end

      private def thresholds_payload
        {
          "passed"    => thresholds_passed?,
          "evaluated" => @thresholds.map { |result| threshold_payload(result) },
          # Same shape as `evaluated`, filtered to the failures, so a consumer
          # can render a failure message without re-implementing the filter.
          "breached" => @thresholds.reject(&.passed?).map { |result| threshold_payload(result) },
        }
      end

      private def threshold_payload(result : ThresholdResult)
        {
          "name"       => result.name,
          "scope"      => result.scope,
          "metric"     => result.metric,
          "comparator" => result.comparator,
          "limit"      => result.limit,
          "actual"     => result.actual,
          "passed"     => result.passed?,
        }
      end

      private def success_status_ranges : Array(String)
        @stats.success_status_ranges.map do |status_range|
          status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
        end
      end

      # CSV -------------------------------------------------------------------

      HEADERS = [
        "url", "duration_mode", "requests", "responses", "transport_errors",
        "elapsed_seconds", "requests_per_second", "transfer_total_bytes",
        "transfer_size_per_request_bytes", "transfer_bytes_per_second",
        "latency_avg_ms", "latency_min_ms", "latency_stdev_ms", "latency_max_ms",
        "latency_p50_ms", "latency_p90_ms", "latency_p95_ms", "latency_p99_ms",
        "latency_p999_ms", "status_successful_count", "status_successful_percent",
        "status_failed_count", "status_failed_percent", "transport_error_percent",
        "status_successes", "status_code_distribution", "transport_error_distribution",
        # v6 columns are appended so header-indexed consumers keep working.
        "schema_version", "cryload_version", "workers", "latency_correction",
        "latency_corrected_p50_ms", "latency_corrected_p90_ms",
        "latency_corrected_p95_ms", "latency_corrected_p99_ms",
        "latency_corrected_p999_ms", "send_delay_p50_ms", "send_delay_p99_ms",
        "rate_requested_per_second", "rate_attained_per_second",
        "rate_attainment_percent", "rate_skipped_requests",
        "rate_schedule_drift_ms", "phase_dns_p50_ms", "phase_connect_p50_ms",
        "phase_tls_p50_ms", "phase_ttfb_p50_ms", "thresholds_passed",
        "thresholds_breached", "exit_code",
      ]

      def to_csv : String
        status_codes = @status_breakdown.map { |entry| "#{entry.code}:#{entry.count}:#{entry.percent}%" }.join(";")
        errors = @error_breakdown.map { |entry| "#{entry.category}:#{entry.count}:#{entry.percent}%" }.join(";")

        row = [
          @stats.url,
          @stats.duration_mode?.to_s,
          @total.to_s,
          @responses.to_s,
          @errors.to_s,
          @elapsed.to_s,
          @rps.to_s,
          @total_bytes.to_s,
          @bytes_per_request.round(2).to_s,
          @bytes_per_second.round(2).to_s,
          @latency.avg.round(2).to_s,
          @latency.min.round(2).to_s,
          @latency.stdev.round(2).to_s,
          @latency.max.round(2).to_s,
          @latency.p(50.0).round(2).to_s,
          @latency.p(90.0).round(2).to_s,
          @latency.p(95.0).round(2).to_s,
          @latency.p(99.0).round(2).to_s,
          @latency.p(99.9).round(2).to_s,
          @ok.to_s,
          Logger.percentage(@ok, @responses).to_s,
          @failed.to_s,
          Logger.percentage(@failed, @responses).to_s,
          Logger.percentage(@errors, @total).to_s,
          success_status_ranges.join(";"),
          status_codes,
          errors,
          SCHEMA_VERSION.to_s,
          Cryload::VERSION,
          @stats.config.workers.to_s,
          @stats.config.latency_correction?.to_s,
          @corrected.p(50.0).round(2).to_s,
          @corrected.p(90.0).round(2).to_s,
          @corrected.p(95.0).round(2).to_s,
          @corrected.p(99.0).round(2).to_s,
          @corrected.p(99.9).round(2).to_s,
          @send_delay.p(50.0).round(2).to_s,
          @send_delay.p(99.0).round(2).to_s,
          @rate.requested.try(&.to_s) || "",
          @rate.attained.round(2).to_s,
          @rate.attainment_percent.try(&.round(2).to_s) || "",
          @rate.skipped_requests.try(&.to_s) || "",
          @rate.schedule_drift_ms.try(&.round(2).to_s) || "",
          @phases["dns"].p(50.0).round(2).to_s,
          @phases["connect"].p(50.0).round(2).to_s,
          @phases["tls"].p(50.0).round(2).to_s,
          @phases["ttfb"].p(50.0).round(2).to_s,
          thresholds_passed?.to_s,
          breached_labels.join(";"),
          @exit_code.value.to_s,
        ]

        CSV.build do |csv|
          csv.row HEADERS
          csv.row row
        end
      end

      # Text ------------------------------------------------------------------

      def print_text
        print_summary
        print_status
        print_transfer
        print_latency
        print_corrected_latency if @rate.limited?
        print_rate if @rate.limited?
        print_phases
        print_histogram_section
        print_distribution
        print_status_distribution
        print_error_distribution
        print_url_breakdown
        print_thresholds
      end

      private def print_summary
        puts "Summary"
        puts "  Total requests: #{@total}"
        puts "  Total time: #{@elapsed}s"
        puts "  Requests/sec: #{@rps}"
        puts "  Responses: #{@responses}"
        puts "  Transport errors: #{@errors} (#{Logger.percentage(@errors, @total)}%)"
        puts "  Fastest: #{Logger.format_latency(@latency.min)} ms"
        puts "  Slowest: #{Logger.format_latency(@latency.max)} ms"
        puts
      end

      private def print_status
        puts "Status"
        puts "  Successful: #{@ok} (#{Logger.percentage(@ok, @responses)}%)"
        puts "  Failed: #{@failed} (#{Logger.percentage(@failed, @responses)}%)"
        puts "  Success statuses: #{success_status_ranges.join(", ")}"
        puts
      end

      private def print_transfer
        puts "Transfer"
        puts "  Total data: #{Logger.format_bytes(@total_bytes)}"
        puts "  Size/request: #{Logger.format_bytes(@bytes_per_request)}"
        puts "  Transfer/sec: #{Logger.format_bytes(@bytes_per_second)}/s"
        puts
      end

      private def print_latency
        puts "Latency (ms)"
        puts "  avg: #{Logger.format_latency(@latency.avg)}   min: #{Logger.format_latency(@latency.min)}   " \
             "stdev: #{Logger.format_latency(@latency.stdev)}   max: #{Logger.format_latency(@latency.max)}"
        puts
        puts "Latency Percentiles (ms)"
        puts "  p50: #{Logger.format_latency(@latency.p(50.0))}   p90: #{Logger.format_latency(@latency.p(90.0))}   " \
             "p95: #{Logger.format_latency(@latency.p(95.0))}"
        puts "  p99: #{Logger.format_latency(@latency.p(99.0))}   p999: #{Logger.format_latency(@latency.p(99.9))}"
        puts
      end

      private def print_corrected_latency
        puts "Corrected Latency Percentiles (ms)"
        puts "  Measured from each request's scheduled send time, so a stalled"
        puts "  target shows up here even when the requests it delayed were fast."
        puts "  p50: #{Logger.format_latency(@corrected.p(50.0))}   p90: #{Logger.format_latency(@corrected.p(90.0))}   " \
             "p95: #{Logger.format_latency(@corrected.p(95.0))}"
        puts "  p99: #{Logger.format_latency(@corrected.p(99.0))}   p999: #{Logger.format_latency(@corrected.p(99.9))}"
        puts "  send delay p99: #{Logger.format_latency(@send_delay.p(99.0))}   max: #{Logger.format_latency(@send_delay.max)}"
        puts
      end

      private def print_rate
        requested = @rate.requested
        return unless requested

        puts "Rate"
        puts "  Requested: #{Logger.format_rate(requested)} req/s"
        puts "  Attained: #{@rate.attained.round(2)} req/s (#{@rate.attainment_percent.try(&.round(2)) || 0.0}%)"
        if scheduled = @rate.scheduled_requests
          skipped = @rate.skipped_requests || 0_i64
          puts "  Scheduled: #{scheduled} requests"
          puts "  Never issued: #{skipped} requests#{skipped > 0 ? " (target could not keep up)" : ""}"
        end
        puts "  Schedule drift: #{Logger.format_latency(@rate.schedule_drift_ms || 0.0)} ms (peak send delay)"
        puts
      end

      private def print_phases
        puts "Latency Phases (ms)"
        puts "  dns/connect/tls are per connection; ttfb/total are per response."
        puts "  #{"phase".ljust(8)} #{"count".rjust(9)} #{"avg".rjust(9)} #{"p50".rjust(9)} #{"p95".rjust(9)} #{"p99".rjust(9)}"
        {"dns", "connect", "tls", "ttfb", "total"}.each do |name|
          view = @phases[name]
          puts "  #{name.ljust(8)} #{view.count.to_s.rjust(9)} " \
               "#{Logger.format_latency(view.avg).rjust(9)} " \
               "#{Logger.format_latency(view.p(50.0)).rjust(9)} " \
               "#{Logger.format_latency(view.p(95.0)).rjust(9)} " \
               "#{Logger.format_latency(view.p(99.0)).rjust(9)}"
        end
        puts
      end

      private def print_histogram_section
        puts "Latency Histogram (ms)"
        Logger.print_histogram @histogram_bins
        puts
      end

      private def print_distribution
        puts "Latency Distribution (ms)"
        {10.0, 25.0, 50.0, 75.0, 90.0, 95.0, 99.0, 99.9}.each do |percentile|
          label = percentile == percentile.trunc ? "#{percentile.to_i}.0" : percentile.to_s
          puts "  #{label}% in #{Logger.format_latency(@latency.p(percentile))}"
        end
        puts
      end

      private def print_status_distribution
        return if @status_breakdown.empty?

        puts "Status Code Distribution"
        @status_breakdown.each do |entry|
          puts "  [#{entry.code}] #{entry.count} responses (#{entry.percent}%)  " \
               "p50 #{Logger.format_latency(entry.p50_ms)}  p99 #{Logger.format_latency(entry.p99_ms)}"
        end
        puts
      end

      private def print_error_distribution
        return if @error_breakdown.empty?

        puts "Error Distribution"
        @error_breakdown.each do |entry|
          puts "  [#{entry.category}] #{entry.count} errors (#{entry.percent}%)"
          if message = entry.sample_message
            puts "      → #{message}"
          end
        end
        puts
      end

      private def print_url_breakdown
        breakdown = @url_breakdown
        return unless breakdown

        puts "Per-URL"
        breakdown.each do |entry|
          puts "  #{entry.url}"
          puts "    requests #{entry.requests}  errors #{entry.transport_errors}  " \
               "fail-rate #{entry.failure_rate_percent}%  rps #{entry.requests_per_second}"
          puts "    p50 #{Logger.format_latency(entry.p50_ms)}  p95 #{Logger.format_latency(entry.p95_ms)}  " \
               "p99 #{Logger.format_latency(entry.p99_ms)}  max #{Logger.format_latency(entry.max_ms)}"
        end
        puts
      end

      private def print_thresholds
        return if @thresholds.empty?

        puts "Thresholds"
        @thresholds.each do |result|
          verdict = result.passed? ? "PASS".colorize(:green) : "FAIL".colorize(:red)
          scope = result.scope == "global" ? "" : " [#{result.scope}]"
          puts "  #{verdict} #{result.metric} #{result.comparator} #{Logger.trim_number(result.limit)}" \
               "#{scope} — actual #{Logger.trim_number(result.actual)}"
        end
        puts
      end
    end

    # Formatting helpers ------------------------------------------------------

    def self.percentage(count : Int64, total : Int64) : Float64
      return 0.0 if total == 0
      ((count.to_f / total) * 100.0).round(2)
    end

    def self.format_bytes(bytes : Int | Int64 | Float64) : String
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

    def self.format_latency(value : Float64) : String
      if value < 10.0
        value.round(3).to_s
      elsif value < 100.0
        value.round(2).to_s
      else
        value.round(1).to_s
      end
    end

    def self.format_span(span : Time::Span?) : String
      return "none" unless span && span.positive?
      Duration.format span
    end

    def self.format_rate(rate : Float64) : String
      trim_number rate
    end

    # Integral values print without a fraction only while they fit an Int64;
    # a finite but huge limit (`--max-p99 1e300`) would overflow `to_i64`.
    def self.trim_number(value : Float64) : String
      value == value.trunc && value.abs < 1e15 ? value.to_i64.to_s : value.round(4).to_s
    end

    def self.print_histogram(histogram_bins)
      max_count = histogram_bins.max_of?(&.count) || 0_i64
      max_label_width = histogram_bins.max_of? { |bin| histogram_label(bin).size } || 0

      histogram_bins.each do |bin|
        width = max_count > 0 ? ((bin.count.to_f / max_count) * 32).round.to_i : 0
        width = 1 if bin.count > 0 && width == 0
        bar = "■" * width
        label = histogram_label(bin).rjust(max_label_width)
        puts "  #{label} [#{bin.count}] |#{bar}"
      end
    end

    def self.format_success_statuses(status_ranges : Array(Range(Int32, Int32))) : String
      status_ranges.map do |status_range|
        status_range.begin == status_range.end ? status_range.begin.to_s : "#{status_range.begin}-#{status_range.end}"
      end.join(", ")
    end

    private def self.histogram_label(bin) : String
      "#{format_latency(bin.end_ms)} ms"
    end
  end
end
