# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = {} of Symbol => String | Int32 | Bool | Float64 | Array(String)
      @show_help = false
      @show_version = false
      @parse_error = false
      prepare_op

      if @show_version
        puts "cryload #{Cryload::VERSION}"
        exit 0
      end

      if @show_help
        exit(@parse_error ? 1 : 0)
      end

      unless Validator.validate(@options) { |message| print_start_message(message) }
        exit 1
      end

      connections = @options[:connections].as(Int32)
      urls = OptionsBuilder.resolve_urls(@options)
      display_url = Cryload.display_url(urls)
      output_format = OptionsBuilder.resolve_output_format(@options)
      method = @options[:method].as(String)
      body = OptionsBuilder.resolve_body(@options)
      timeout_seconds = @options[:timeout]?.try(&.as(Int32))
      rate_limit = @options[:rate]?.try(&.as(Int32))
      insecure = @options[:insecure]?.try(&.as(Bool)) || false
      follow_redirects = @options[:follow_redirects]?.try(&.as(Bool)) || false
      success_status_ranges = Validator.parse_success_status_ranges(@options[:success_status]?.try(&.as(String)))
      headers = OptionsBuilder.build_headers(@options, @options[:headers].as(Array(String)), @options[:cookies].as(Array(String)))
      ci_thresholds = OptionsBuilder.build_ci_thresholds(@options)
      warmup_seconds = @options[:warmup]?.try(&.as(Int32)) || 0
      progress = @options[:progress].as(Bool)
      random_path = @options[:random_path]?.try(&.as(Bool)) || false
      proxy = OptionsBuilder.resolve_proxy(@options)

      if @options.has_key?(:duration)
        duration = @options[:duration].as(Int32)
        Cryload::LoadGenerator.new display_url, nil, connections, duration, output_format, method, body, headers, timeout_seconds, insecure, rate_limit, follow_redirects, success_status_ranges, ci_thresholds, urls, warmup_seconds, proxy, progress, random_path
      else
        numbers = @options[:numbers].as(Int32)
        Cryload::LoadGenerator.new display_url, numbers, connections, nil, output_format, method, body, headers, timeout_seconds, insecure, rate_limit, follow_redirects, success_status_ranges, ci_thresholds, urls, warmup_seconds, proxy, progress, random_path
      end
    end

    private def prepare_op
      @options[:connections] = 10
      @options[:method] = "GET"
      @options[:headers] = [] of String
      @options[:cookies] = [] of String
      @options[:progress] = true
      begin
        OptionParser.parse(ARGV) do |opts|
          opts.banner = "Cross-platform HTTP load testing CLI: a modern ab/wrk alternative with machine-readable reports for CI/CD\n\nUsage: cryload <url> [options]"

          opts.on("-n NUMBERS", "--numbers NUMBERS", "Number of requests to make") do |v|
            @options[:numbers] = v.to_i
          end

          opts.on("-c CONNECTIONS", "--connections CONNECTIONS", "Number of concurrent connections (default: 10)") do |v|
            @options[:connections] = v.to_i
          end

          opts.on("-d SECONDS", "--duration SECONDS", "Duration of test in seconds (e.g. -d 10 for 10 seconds)") do |v|
            @options[:duration] = v.to_i
          end

          opts.on("-m METHOD", "--method METHOD", "HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS)") do |v|
            @options[:method] = v.upcase
          end

          opts.on("-b BODY", "--body BODY", "HTTP request body") do |v|
            @options[:body] = v
          end

          opts.on("--body-file PATH", "Read HTTP request body from file") do |v|
            @options[:body_file] = v
          end

          opts.on("-H HEADER", "--header HEADER", "HTTP header, repeatable (e.g. -H 'Authorization: Bearer token')") do |v|
            headers = @options[:headers].as(Array(String))
            headers << v
          end

          opts.on("--user-agent VALUE", "Set the User-Agent header") do |v|
            @options[:user_agent] = v
          end

          opts.on("--host-header VALUE", "Override the Host header") do |v|
            @options[:host_header] = v
          end

          opts.on("-a USERPASS", "--basic-auth USERPASS", "HTTP Basic auth in the form 'user:password'") do |v|
            @options[:basic_auth] = v
          end

          opts.on("--timeout SECONDS", "Client connect/read timeout in seconds") do |v|
            @options[:timeout] = v.to_i
          end

          opts.on("-q RATE", "--rate RATE", "Total request rate limit in requests/sec") do |v|
            @options[:rate] = v.to_i
          end

          opts.on("-L", "--follow-redirects", "Follow HTTP redirects (up to 5 hops)") do
            @options[:follow_redirects] = true
          end

          opts.on("--output-format FORMAT", "Output format: text, json, csv, quiet") do |v|
            @options[:output_format] = v.downcase
          end

          opts.on("--success-status CODES", "Successful status codes/ranges (e.g. 200-299,301,304)") do |v|
            @options[:success_status] = v
          end

          opts.on("--insecure", "Accept invalid TLS certificates (HTTPS only)") do
            @options[:insecure] = true
          end

          opts.on("--json", "Output final results as JSON") do
            @options[:json] = true
          end

          opts.on("--fail-on-error", "Exit with code 1 when any HTTP or transport error occurs") do
            @options[:fail_on_error] = true
          end

          opts.on("--fail-on-transport-error", "Exit with code 1 when any transport error occurs") do
            @options[:fail_on_transport_error] = true
          end

          opts.on("--max-fail-rate PERCENT", "Exit with code 1 when failure rate exceeds PERCENT") do |v|
            @options[:max_fail_rate] = v.to_f
          end

          opts.on("--max-p99 MS", "Exit with code 1 when p99 latency exceeds MS milliseconds") do |v|
            @options[:max_p99_ms] = v.to_f
          end

          opts.on("--warmup SECONDS", "Warm up before the timed benchmark (seconds)") do |v|
            @options[:warmup] = v.to_i
          end

          opts.on("--proxy URL", "HTTP(S) proxy (e.g. http://127.0.0.1:8080 or http://user:pass@proxy:8080)") do |v|
            @options[:proxy] = v
          end

          opts.on("--no-progress", "Disable live progress on stderr") do
            @options[:progress] = false
          end

          opts.on("--progress", "Show live progress on stderr during the run (default)") do
            @options[:progress] = true
          end

          opts.on("--cookie COOKIE", "Cookie value, repeatable (name=value)") do |v|
            cookies = @options[:cookies].as(Array(String))
            cookies << v
          end

          opts.on("--urls-file PATH", "Load target URLs from file (one http(s) URL per line, # comments allowed)") do |v|
            @options[:urls_file] = v
          end

          opts.on("--random-path", "Append a random path segment to each request URL") do
            @options[:random_path] = true
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
        end.parse
      rescue ex : OptionParser::Exception
        STDERR.puts ex.message.to_s.colorize(:red)
        STDERR.puts "Try 'cryload -h' for usage.".colorize(:red)
        @show_help = true
        @parse_error = true
      end

      if (url = ARGV[0]?) && !url.starts_with?("-")
        @options[:server] = url
      end
    end

    private def print_start_message(message : String)
      return unless OptionsBuilder.resolve_output_format(@options) == "text"
      puts message.colorize(:green)
    end
  end
end
