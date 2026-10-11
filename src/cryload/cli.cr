# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = Options.new
      @show_help = false
      @show_version = false
      @parse_error = false
      prepare_op

      if @show_version
        puts "cryload #{Cryload::VERSION}"
        exit ExitCode::Ok.value
      end

      if @show_help
        exit(@parse_error ? ExitCode::ConfigError.value : ExitCode::Ok.value)
      end

      unless Validator.validate(@options) { |message| print_start_message(message) }
        exit ExitCode::ConfigError.value
      end

      urls = OptionsBuilder.resolve_urls(@options)

      Cryload::LoadGenerator.new(
        host: Cryload.display_url(urls),
        request_number: @options.numbers,
        connections: @options.connections,
        duration: @options.duration,
        output_format: OptionsBuilder.resolve_output_format(@options),
        http_method: @options.method,
        http_body: OptionsBuilder.resolve_body(@options),
        http_headers: OptionsBuilder.build_headers(@options),
        timeouts: OptionsBuilder.build_timeouts(@options),
        insecure: @options.insecure?,
        rate_limit: @options.rate,
        follow_redirects: @options.follow_redirects?,
        success_status_ranges: Validator.parse_success_status_ranges(@options.success_status),
        ci_thresholds: OptionsBuilder.build_ci_thresholds(@options),
        urls: urls,
        warmup: @options.warmup || Time::Span.zero,
        proxy: OptionsBuilder.resolve_proxy(@options),
        progress: OptionsBuilder.resolve_progress(@options),
        random_path: @options.random_path?,
        disable_keepalive: @options.disable_keepalive?,
        latency_correction: @options.latency_correction?,
        workers: @options.workers,
      )
    end

    private def prepare_op
      begin
        OptionParser.parse(ARGV) do |opts|
          opts.banner = "HTTP load testing for CI/CD: honest latency, CI thresholds, JSON/CSV. A modern ab/wrk alternative.\n\nUsage: cryload <url> [options]"

          opts.on("-n NUMBERS", "--numbers NUMBERS", "Number of requests to make") do |v|
            @options.numbers = parse_int(v, "-n/--numbers")
          end

          opts.on("-c CONNECTIONS", "--connections CONNECTIONS", "Number of concurrent connections (default: 10)") do |v|
            @options.connections = parse_int(v, "-c/--connections")
          end

          opts.on("-d DURATION", "--duration DURATION", "Duration of test (30, 30s, 2m, 1h30m; bare number = seconds)") do |v|
            @options.duration = parse_duration(v, "-d/--duration")
          end

          opts.on("--workers COUNT", "Load-generator threads (default: min(cpu cores, connections))") do |v|
            @options.workers = parse_int(v, "--workers")
          end

          opts.on("-m METHOD", "--method METHOD", "HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS)") do |v|
            @options.method = v.upcase
          end

          opts.on("-b BODY", "--body BODY", "HTTP request body") do |v|
            @options.body = v
          end

          opts.on("--body-file PATH", "Read HTTP request body from file") do |v|
            @options.body_file = v
          end

          opts.on("--body-stdin", "Read HTTP request body from standard input") do
            @options.body_stdin = true
          end

          opts.on("-H HEADER", "--header HEADER", "HTTP header, repeatable (e.g. -H 'Authorization: Bearer token')") do |v|
            @options.headers << v
          end

          opts.on("--user-agent VALUE", "Set the User-Agent header") do |v|
            @options.user_agent = v
          end

          opts.on("--host-header VALUE", "Override the Host header") do |v|
            @options.host_header = v
          end

          opts.on("-a USERPASS", "--basic-auth USERPASS", "HTTP Basic auth in the form 'user:password'") do |v|
            @options.basic_auth = v
          end

          opts.on("--timeout DURATION", "Client connect/read/write timeout (e.g. 5, 5s, 500ms)") do |v|
            @options.timeout = parse_duration(v, "--timeout")
          end

          opts.on("--request-timeout DURATION", "Total deadline per request including body download") do |v|
            @options.request_timeout = parse_duration(v, "--request-timeout")
          end

          opts.on("-q RATE", "--rate RATE", "Total request rate limit in requests/sec (fractional allowed)") do |v|
            @options.rate = parse_float(v, "-q/--rate")
          end

          opts.on("-L", "--follow-redirects", "Follow HTTP redirects (up to 5 hops)") do
            @options.follow_redirects = true
          end

          opts.on("--disable-keepalive", "Open a new connection for every request (sends 'Connection: close')") do
            @options.disable_keepalive = true
          end

          opts.on("--output-format FORMAT", "Output format: text, json, csv, quiet") do |v|
            @options.output_format = v.downcase
          end

          opts.on("--success-status CODES", "Successful status codes/ranges (e.g. 200-299,301,304)") do |v|
            @options.success_status = v
          end

          opts.on("--insecure", "Accept invalid TLS certificates (HTTPS only)") do
            @options.insecure = true
          end

          opts.on("--json", "Output final results as JSON") do
            @options.json = true
          end

          opts.on("--latency-correction MODE", "Gate on coordinated-omission corrected latency: on (default) or off") do |v|
            @options.latency_correction = parse_toggle(v, "--latency-correction")
          end

          opts.on("--fail-on-error", "Exit 1 when any HTTP or transport error occurs") do
            @options.fail_on_error = true
          end

          opts.on("--fail-on-transport-error", "Exit 1 when any transport error occurs") do
            @options.fail_on_transport_error = true
          end

          opts.on("--fail-on-rate-miss", "Exit 1 when the attained rate falls below --rate") do
            @options.fail_on_rate_miss = true
          end

          opts.on("--max-fail-rate PERCENT", "Exit 1 when failure rate exceeds PERCENT") do |v|
            @options.max_fail_rate = parse_float(v, "--max-fail-rate")
          end

          opts.on("--min-rps RATE", "Exit 1 when throughput falls below RATE requests/sec") do |v|
            @options.min_rps = parse_float(v, "--min-rps")
          end

          {
            "--max-p50"     => {Threshold::Metric::P50, "p50"},
            "--max-p75"     => {Threshold::Metric::P75, "p75"},
            "--max-p90"     => {Threshold::Metric::P90, "p90"},
            "--max-p95"     => {Threshold::Metric::P95, "p95"},
            "--max-p99"     => {Threshold::Metric::P99, "p99"},
            "--max-p999"    => {Threshold::Metric::P999, "p999"},
            "--max-avg"     => {Threshold::Metric::Avg, "average"},
            "--max-latency" => {Threshold::Metric::MaxLatency, "slowest"},
          }.each do |flag, (metric, label)|
            opts.on("#{flag} MS", "Exit 1 when #{label} latency exceeds MS milliseconds") do |v|
              @options.max_latency[metric] = parse_float(v, flag)
            end
          end

          opts.on("--url-threshold RULE", "Per-endpoint gate: 'PATTERN METRIC VALUE', repeatable") do |v|
            @options.url_thresholds << v
          end

          opts.on("--warmup DURATION", "Warm up before the timed benchmark (e.g. 3, 3s)") do |v|
            @options.warmup = parse_duration(v, "--warmup")
          end

          opts.on("--proxy URL", "HTTP(S) proxy (e.g. http://127.0.0.1:8080 or http://user:pass@proxy:8080)") do |v|
            @options.proxy = v
          end

          opts.on("--no-progress", "Disable live progress on stderr") do
            @options.progress = false
          end

          opts.on("--progress", "Force live progress on stderr (default: only when stderr is a TTY)") do
            @options.progress = true
          end

          opts.on("--cookie COOKIE", "Cookie value, repeatable (name=value)") do |v|
            @options.cookies << v
          end

          opts.on("--urls-file PATH", "Load target URLs from file (one http(s) URL per line, # comments allowed)") do |v|
            @options.urls_file = v
          end

          opts.on("--random-path", "Append a random path segment to each request URL") do
            @options.random_path = true
          end

          opts.on("-h", "--help", "Print Help") do
            puts opts
            @show_help = true
          end

          opts.on("-V", "--version", "Print version") do
            @show_version = true
          end

          if ARGV.empty?
            puts opts
            @show_help = true
          end
        end
      rescue ex : OptionParser::Exception
        STDERR.puts ex.message.to_s.colorize(:red)
        STDERR.puts "Try 'cryload -h' for usage.".colorize(:red)
        @show_help = true
        @parse_error = true
      end

      if (url = ARGV[0]?) && !url.starts_with?("-")
        @options.server = url
      end
    end

    private def parse_int(value : String, flag : String) : Int32
      value.to_i? || raise OptionParser::Exception.new("Invalid value '#{value}' for #{flag}: expected an integer")
    end

    # `String#to_f?` accepts "nan" and "inf"; neither is a usable rate or limit,
    # and both crash the report (JSON cannot encode them) after the whole run.
    private def parse_float(value : String, flag : String) : Float64
      number = value.to_f?
      return number if number && number.finite?
      raise OptionParser::Exception.new("Invalid value '#{value}' for #{flag}: expected a number")
    end

    private def parse_duration(value : String, flag : String) : Time::Span
      Duration.parse(value, flag)
    rescue ex : ArgumentError
      raise OptionParser::Exception.new(ex.message)
    end

    private def parse_toggle(value : String, flag : String) : Bool
      case value.downcase
      when "on", "true", "1"   then true
      when "off", "false", "0" then false
      else
        raise OptionParser::Exception.new("Invalid value '#{value}' for #{flag}: expected 'on' or 'off'")
      end
    end

    private def print_start_message(message : String)
      return unless OptionsBuilder.resolve_output_format(@options) == "text"
      puts message.colorize(:green)
    end
  end
end
