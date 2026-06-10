module Cryload
  class Cli
    module Validator
      extend self

      VALID_METHODS        = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}
      VALID_OUTPUT_FORMATS = {"text", "json", "csv", "quiet"}

      def validate(options : Options, &on_ready : String ->)
        return false unless validate_url_sources(options)
        return false unless validate_request_settings(options)
        return false unless validate_output_settings(options)
        return false unless validate_threshold_settings(options)
        return false unless validate_proxy_and_cookies(options)
        validate_run_mode(options, on_ready)
      end

      private def validate_url_sources(options) : Bool
        unless options.server || options.urls_file
          error "Usage: cryload <url> [options]  (or --urls-file PATH)"
          error "Example: cryload http://localhost:3000 -n 100"
          return false
        end

        if server = options.server
          unless valid_url?(server)
            error "Invalid URL '#{server}'. Use an absolute http(s) URL (e.g. http://localhost:3000)."
            return false
          end
        end

        if urls_file = options.urls_file
          unless File.file?(urls_file)
            error "URLs file not found: #{urls_file}"
            return false
          end

          begin
            OptionsBuilder.resolve_urls(options)
          rescue ex : ArgumentError
            error ex.message.to_s
            return false
          end
        end

        true
      end

      private def validate_request_settings(options) : Bool
        if options.connections <= 0
          error "Connections must be greater than 0."
          return false
        end

        unless VALID_METHODS.includes?(options.method)
          error "Invalid HTTP method '#{options.method}'. Allowed: #{VALID_METHODS.join(", ")}"
          return false
        end

        if options.headers.any? { |header| !valid_header?(header) }
          error "Invalid header format. Use 'Key: Value' (e.g. -H 'Authorization: Bearer token')."
          return false
        end

        return false unless validate_user_agent(options)
        return false unless validate_host_header(options)
        return false unless validate_disable_keepalive(options)
        return false unless validate_body_sources(options)
        return false unless validate_basic_auth(options)
        return false unless validate_timeout(options)

        true
      end

      private def validate_user_agent(options) : Bool
        return true unless user_agent = options.user_agent

        if user_agent.strip.empty?
          error "User-Agent must not be empty."
          return false
        end

        if header_name_present?(options.headers, "User-Agent")
          error "Please specify only one User-Agent source: either '--user-agent' or '-H User-Agent: ...'."
          return false
        end

        true
      end

      private def validate_host_header(options) : Bool
        return true unless host_header = options.host_header

        if host_header.strip.empty?
          error "Host header must not be empty."
          return false
        end

        if header_name_present?(options.headers, "Host")
          error "Please specify only one Host header source: either '--host-header' or '-H Host: ...'."
          return false
        end

        true
      end

      private def validate_disable_keepalive(options) : Bool
        return true unless options.disable_keepalive?

        if header_name_present?(options.headers, "Connection")
          error "Please specify only one Connection source: either '--disable-keepalive' or '-H Connection: ...'."
          return false
        end

        true
      end

      private def validate_body_sources(options) : Bool
        sources = 0
        sources += 1 if options.body
        sources += 1 if options.body_file
        sources += 1 if options.body_stdin?

        if sources > 1
          error "Please specify only one body source: '--body', '--body-file', or '--body-stdin'."
          return false
        end

        if body_file = options.body_file
          unless File.file?(body_file)
            error "Body file not found: #{body_file}"
            return false
          end
        end

        true
      end

      private def validate_basic_auth(options) : Bool
        return true unless auth = options.basic_auth

        unless valid_basic_auth?(auth)
          error "Invalid basic auth format. Use 'user:password'."
          return false
        end

        if header_name_present?(options.headers, "Authorization")
          error "Please specify only one authorization source: either '--basic-auth' or '-H Authorization: ...'."
          return false
        end

        true
      end

      private def validate_timeout(options) : Bool
        if timeout = options.timeout
          if timeout <= 0
            error "Timeout must be greater than 0 seconds."
            return false
          end
        end

        true
      end

      private def validate_output_settings(options) : Bool
        if output_format = options.output_format
          unless VALID_OUTPUT_FORMATS.includes?(output_format)
            error "Invalid output format '#{output_format}'. Allowed: #{VALID_OUTPUT_FORMATS.join(", ")}"
            return false
          end

          if options.json? && output_format != "json"
            error "Please specify only one JSON output source: either '--json' or '--output-format json'."
            return false
          end
        end

        if success_status = options.success_status
          begin
            parse_success_status_ranges(success_status)
          rescue ex : ArgumentError
            error ex.message.to_s
            return false
          end
        end

        true
      end

      private def validate_threshold_settings(options) : Bool
        if rate = options.rate
          if rate <= 0
            error "Rate must be greater than 0 requests/sec."
            return false
          end
        end

        if max_fail_rate = options.max_fail_rate
          if max_fail_rate < 0.0 || max_fail_rate > 100.0
            error "Max fail rate must be between 0 and 100."
            return false
          end
        end

        if max_p99_ms = options.max_p99_ms
          if max_p99_ms <= 0.0
            error "Max p99 latency must be greater than 0 milliseconds."
            return false
          end
        end

        if warmup = options.warmup
          if warmup < 0
            error "Warmup must be 0 or greater."
            return false
          end
        end

        true
      end

      private def validate_proxy_and_cookies(options) : Bool
        if proxy = options.proxy
          unless valid_proxy?(proxy)
            error "Invalid proxy URL '#{proxy}'. Use http(s)://host[:port] (e.g. http://127.0.0.1:8080)."
            return false
          end
        end

        if options.cookies.any?(&.strip.empty?)
          error "Cookie values must not be empty."
          return false
        end

        unless options.cookies.all? { |cookie| valid_cookie?(cookie) }
          error "Invalid cookie format. Use 'name=value'."
          return false
        end

        true
      end

      private def validate_run_mode(options, on_ready : String ->) : Bool
        duration = options.duration
        numbers = options.numbers

        if duration && numbers
          error "Please specify only one mode: either '-n' or '-d'."
          return false
        end

        if duration
          if duration <= 0
            error "Duration must be greater than 0."
            return false
          end
          on_ready.call("Preparing to make it CRY for #{duration} seconds with #{options.connections} connections!")
          true
        elsif numbers
          if numbers <= 0
            error "Number of requests must be greater than 0."
            return false
          end
          on_ready.call("Preparing to make it CRY for #{numbers} requests with #{options.connections} connections!")
          true
        else
          error "You have to specify '-n' (number of requests) or '-d' (duration in seconds)"
          false
        end
      end

      def valid_url?(url : String)
        uri = URI.parse(url)
        return false if uri.host.nil?
        uri.scheme == "http" || uri.scheme == "https"
      rescue URI::Error
        false
      end

      def valid_proxy?(url : String)
        uri = URI.parse(url)
        return false if uri.host.nil?
        uri.scheme == "http" || uri.scheme == "https"
      rescue URI::Error
        false
      end

      def valid_cookie?(cookie : String)
        parts = cookie.split("=", 2)
        return false if parts.size != 2
        !parts[0].strip.empty?
      end

      def valid_header?(header : String)
        parts = header.split(":", 2)
        return false if parts.size != 2
        key = parts[0].strip
        value = parts[1].strip
        !key.empty? && !value.empty?
      end

      def valid_basic_auth?(auth : String)
        parts = auth.split(":", 2)
        return false if parts.size != 2
        !parts[0].empty?
      end

      def header_name_present?(headers : Array(String), expected_name : String)
        expected_name_downcase = expected_name.downcase
        headers.any? do |header|
          header.split(":", 2)[0]?.try(&.strip.downcase) == expected_name_downcase
        end
      end

      def parse_success_status_ranges(raw_value : String?)
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

      private def error(message : String)
        STDERR.puts message.colorize(:red)
      end
    end
  end
end
