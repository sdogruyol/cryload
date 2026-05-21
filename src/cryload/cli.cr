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

      unless input_valid?
        exit 1
      end

      connections = @options[:connections].as(Int32)
      urls = resolve_urls
      display_url = Cryload.display_url(urls)
      output_format = resolve_output_format
      method = @options[:method].as(String)
      body = resolve_body
      timeout_seconds = @options[:timeout]?.try(&.as(Int32))
      rate_limit = @options[:rate]?.try(&.as(Int32))
      insecure = @options[:insecure]?.try(&.as(Bool)) || false
      follow_redirects = @options[:follow_redirects]?.try(&.as(Bool)) || false
      success_status_ranges = parse_success_status_ranges(@options[:success_status]?.try(&.as(String)))
      headers = build_headers(@options[:headers].as(Array(String)), @options[:cookies].as(Array(String)))
      ci_thresholds = build_ci_thresholds
      warmup_seconds = @options[:warmup]?.try(&.as(Int32)) || 0
      progress = @options[:progress].as(Bool)
      random_path = @options[:random_path]?.try(&.as(Bool)) || false
      proxy = resolve_proxy

      if @options.has_key?(:duration)
        duration = @options[:duration].as(Int32)
        Cryload::LoadGenerator.new display_url, nil, connections, duration, output_format, method, body, headers, timeout_seconds, insecure, rate_limit, follow_redirects, success_status_ranges, ci_thresholds, urls, warmup_seconds, proxy, progress, random_path
      else
        numbers = @options[:numbers].as(Int32)
        Cryload::LoadGenerator.new display_url, numbers, connections, nil, output_format, method, body, headers, timeout_seconds, insecure, rate_limit, follow_redirects, success_status_ranges, ci_thresholds, urls, warmup_seconds, proxy, progress, random_path
      end
    end

    # Prepares OptionParser
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

      # First positional argument is the target URL
      if (url = ARGV[0]?) && !url.starts_with?("-")
        @options[:server] = url
      end
    end

    # Validate the input from command line
    private def input_valid?
      unless @options.has_key?(:server) || @options.has_key?(:urls_file)
        STDERR.puts "Usage: cryload <url> [options]  (or --urls-file PATH)".colorize(:red)
        STDERR.puts "Example: cryload http://localhost:3000 -n 100".colorize(:red)
        return false
      end

      if @options.has_key?(:server)
        server = @options[:server].as(String)
        unless valid_url?(server)
          STDERR.puts "Invalid URL '#{server}'. Use an absolute http(s) URL (e.g. http://localhost:3000).".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:urls_file)
        urls_file = @options[:urls_file].as(String)
        unless File.file?(urls_file)
          STDERR.puts "URLs file not found: #{urls_file}".colorize(:red)
          return false
        end

        begin
          resolve_urls
        rescue ex : ArgumentError
          STDERR.puts ex.message.to_s.colorize(:red)
          return false
        end
      end

      connections = @options[:connections].as(Int32)
      if connections <= 0
        STDERR.puts "Connections must be greater than 0.".colorize(:red)
        return false
      end

      method = @options[:method].as(String)
      valid_methods = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}
      unless valid_methods.includes?(method)
        STDERR.puts "Invalid HTTP method '#{method}'. Allowed: #{valid_methods.join(", ")}".colorize(:red)
        return false
      end

      headers = @options[:headers].as(Array(String))
      if headers.any? { |header| !valid_header?(header) }
        STDERR.puts "Invalid header format. Use 'Key: Value' (e.g. -H 'Authorization: Bearer token').".colorize(:red)
        return false
      end

      if @options.has_key?(:user_agent)
        user_agent = @options[:user_agent].as(String)
        if user_agent.strip.empty?
          STDERR.puts "User-Agent must not be empty.".colorize(:red)
          return false
        end

        if header_name_present?(headers, "User-Agent")
          STDERR.puts "Please specify only one User-Agent source: either '--user-agent' or '-H User-Agent: ...'.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:host_header)
        host_header = @options[:host_header].as(String)
        if host_header.strip.empty?
          STDERR.puts "Host header must not be empty.".colorize(:red)
          return false
        end

        if header_name_present?(headers, "Host")
          STDERR.puts "Please specify only one Host header source: either '--host-header' or '-H Host: ...'.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:body) && @options.has_key?(:body_file)
        STDERR.puts "Please specify only one body source: either '--body' or '--body-file'.".colorize(:red)
        return false
      end

      if @options.has_key?(:body_file)
        body_file = @options[:body_file].as(String)
        unless File.file?(body_file)
          STDERR.puts "Body file not found: #{body_file}".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:basic_auth)
        auth = @options[:basic_auth].as(String)
        unless valid_basic_auth?(auth)
          STDERR.puts "Invalid basic auth format. Use 'user:password'.".colorize(:red)
          return false
        end

        if headers.any? { |header| header.split(":", 2)[0]?.try(&.strip.downcase) == "authorization" }
          STDERR.puts "Please specify only one authorization source: either '--basic-auth' or '-H Authorization: ...'.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:timeout)
        timeout = @options[:timeout].as(Int32)
        if timeout <= 0
          STDERR.puts "Timeout must be greater than 0 seconds.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:output_format)
        output_format = @options[:output_format].as(String)
        valid_formats = {"text", "json", "csv", "quiet"}
        unless valid_formats.includes?(output_format)
          STDERR.puts "Invalid output format '#{output_format}'. Allowed: #{valid_formats.join(", ")}".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:json) && @options.has_key?(:output_format)
        output_format = @options[:output_format].as(String)
        if output_format != "json"
          STDERR.puts "Please specify only one JSON output source: either '--json' or '--output-format json'.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:success_status)
        begin
          parse_success_status_ranges(@options[:success_status].as(String))
        rescue ex : ArgumentError
          STDERR.puts ex.message.to_s.colorize(:red)
          return false
        end
      end

      if @options.has_key?(:rate)
        rate = @options[:rate].as(Int32)
        if rate <= 0
          STDERR.puts "Rate must be greater than 0 requests/sec.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:max_fail_rate)
        max_fail_rate = @options[:max_fail_rate].as(Float64)
        if max_fail_rate < 0.0 || max_fail_rate > 100.0
          STDERR.puts "Max fail rate must be between 0 and 100.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:max_p99_ms)
        max_p99_ms = @options[:max_p99_ms].as(Float64)
        if max_p99_ms <= 0.0
          STDERR.puts "Max p99 latency must be greater than 0 milliseconds.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:warmup)
        warmup = @options[:warmup].as(Int32)
        if warmup < 0
          STDERR.puts "Warmup must be 0 or greater.".colorize(:red)
          return false
        end
      end

      if @options.has_key?(:proxy)
        proxy = @options[:proxy].as(String)
        unless valid_proxy?(proxy)
          STDERR.puts "Invalid proxy URL '#{proxy}'. Use http(s)://host[:port] (e.g. http://127.0.0.1:8080).".colorize(:red)
          return false
        end
      end

      cookies = @options[:cookies].as(Array(String))
      if cookies.any? { |cookie| cookie.strip.empty? }
        STDERR.puts "Cookie values must not be empty.".colorize(:red)
        return false
      end

      unless cookies.all? { |cookie| valid_cookie?(cookie) }
        STDERR.puts "Invalid cookie format. Use 'name=value'.".colorize(:red)
        return false
      end

      if @options.has_key?(:duration) && @options.has_key?(:numbers)
        STDERR.puts "Please specify only one mode: either '-n' or '-d'.".colorize(:red)
        return false
      end

      if @options.has_key?(:duration)
        duration = @options[:duration].as(Int32)
        if duration <= 0
          STDERR.puts "Duration must be greater than 0.".colorize(:red)
          return false
        end
        print_start_message("Preparing to make it CRY for #{@options[:duration]} seconds with #{@options[:connections]} connections!")
        true
      elsif @options.has_key?(:numbers)
        numbers = @options[:numbers].as(Int32)
        if numbers <= 0
          STDERR.puts "Number of requests must be greater than 0.".colorize(:red)
          return false
        end
        print_start_message("Preparing to make it CRY for #{@options[:numbers]} requests with #{@options[:connections]} connections!")
        true
      else
        STDERR.puts "You have to specify '-n' (number of requests) or '-d' (duration in seconds)".colorize(:red)
        false
      end
    end

    private def print_start_message(message : String)
      return unless resolve_output_format == "text"
      puts message.colorize(:green)
    end

    private def json_output?
      resolve_output_format == "json"
    end

    private def resolve_output_format
      return "json" if @options[:json]?.try(&.as(Bool))
      @options[:output_format]?.try(&.as(String)) || "text"
    end

    private def build_ci_thresholds : CiThresholds
      CiThresholds.new(
        fail_on_error: @options[:fail_on_error]?.try(&.as(Bool)) || false,
        fail_on_transport_error: @options[:fail_on_transport_error]?.try(&.as(Bool)) || false,
        max_fail_rate: @options[:max_fail_rate]?.try(&.as(Float64)),
        max_p99_ms: @options[:max_p99_ms]?.try(&.as(Float64)),
      )
    end

    private def parse_success_status_ranges(raw_value : String?)
      return [200..299] of Range(Int32, Int32) unless raw_value

      parts = raw_value.split(",").map(&.strip).reject(&.empty?)
      raise ArgumentError.new("Success status list must not be empty.") if parts.empty?

      parts.map do |part|
        if part.includes?("-")
          bounds = part.split("-", 2).map(&.strip)
          raise ArgumentError.new("Invalid success status range '#{part}'. Use formats like '200-299' or '301'.") unless bounds.size == 2
          start_code = parse_status_code(bounds[0], part)
          end_code = parse_status_code(bounds[1], part)
          raise ArgumentError.new("Invalid success status range '#{part}'. Start must be less than or equal to end.") if start_code > end_code
          start_code..end_code
        else
          status_code = parse_status_code(part, part)
          status_code..status_code
        end
      end
    end

    private def parse_status_code(value : String, source : String)
      status_code = value.to_i?
      raise ArgumentError.new("Invalid success status '#{source}'. Use HTTP status codes like '200', '204', or ranges like '300-399'.") unless status_code
      unless (100..599).includes?(status_code)
        raise ArgumentError.new("Success status '#{source}' is out of range. Use codes between 100 and 599.")
      end
      status_code
    end

    private def resolve_body
      body = @options[:body]?.try(&.as(String))
      return body if body

      body_file = @options[:body_file]?.try(&.as(String))
      return nil unless body_file

      File.read(body_file)
    end

    private def build_headers(raw_headers : Array(String), cookies : Array(String))
      headers = parse_headers(raw_headers)
      if host_header = @options[:host_header]?.try(&.as(String))
        headers["Host"] = host_header
      end
      if user_agent = @options[:user_agent]?.try(&.as(String))
        headers["User-Agent"] = user_agent
      end
      if auth = @options[:basic_auth]?.try(&.as(String))
        headers["Authorization"] = "Basic #{Base64.strict_encode(auth)}"
      end
      unless cookies.empty?
        existing = headers["Cookie"]?
        cookie_values = existing ? [existing] + cookies : cookies
        headers["Cookie"] = cookie_values.join("; ")
      end
      headers
    end

    private def parse_headers(raw_headers : Array(String))
      headers = HTTP::Headers.new
      raw_headers.each do |header|
        parts = header.split(":", 2)
        next if parts.size != 2
        key = parts[0].strip
        value = parts[1].strip
        headers[key] = value
      end
      headers
    end

    private def valid_header?(header : String)
      parts = header.split(":", 2)
      return false if parts.size != 2
      key = parts[0].strip
      value = parts[1].strip
      !key.empty? && !value.empty?
    end

    private def valid_basic_auth?(auth : String)
      parts = auth.split(":", 2)
      return false if parts.size != 2
      !parts[0].empty?
    end

    private def header_name_present?(headers : Array(String), expected_name : String)
      expected_name_downcase = expected_name.downcase
      headers.any? do |header|
        header.split(":", 2)[0]?.try(&.strip.downcase) == expected_name_downcase
      end
    end

    private def valid_url?(url : String)
      uri = URI.parse(url)
      return false if uri.host.nil?
      uri.scheme == "http" || uri.scheme == "https"
    rescue URI::Error
      false
    end

    private def valid_proxy?(url : String)
      uri = URI.parse(url)
      return false if uri.host.nil?
      uri.scheme == "http" || uri.scheme == "https"
    rescue URI::Error
      false
    end

    private def valid_cookie?(cookie : String)
      parts = cookie.split("=", 2)
      return false if parts.size != 2
      !parts[0].strip.empty?
    end

    private def resolve_urls : Array(URI)
      urls = [] of URI
      if path = @options[:urls_file]?.try(&.as(String))
        urls.concat Cryload.load_urls_from_file(path)
      end
      if server = @options[:server]?.try(&.as(String))
        urls.unshift URI.parse(server)
      end
      urls
    end

    private def resolve_proxy : URI?
      raw = @options[:proxy]?.try(&.as(String))
      return nil unless raw
      URI.parse(raw)
    end
  end
end
