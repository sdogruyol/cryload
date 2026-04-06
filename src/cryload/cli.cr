# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = {} of Symbol => String | Int32 | Bool | Array(String)
      @show_help = false
      @parse_error = false
      prepare_op

      if @show_help
        exit(@parse_error ? 1 : 0)
      end

      unless input_valid?
        exit 1
      end

      connections = @options[:connections].as(Int32)
      server = @options[:server].as(String)
      json_output = @options[:json]?.try(&.as(Bool)) || false
      method = @options[:method].as(String)
      body = @options[:body]?.try(&.as(String))
      timeout_seconds = @options[:timeout]?.try(&.as(Int32))
      rate_limit = @options[:rate]?.try(&.as(Int32))
      insecure = @options[:insecure]?.try(&.as(Bool)) || false
      headers = parse_headers(@options[:headers].as(Array(String)))
      if @options.has_key?(:duration)
        duration = @options[:duration].as(Int32)
        Cryload::LoadGenerator.new server, nil, connections, duration, json_output, method, body, headers, timeout_seconds, insecure, rate_limit
      else
        numbers = @options[:numbers].as(Int32)
        Cryload::LoadGenerator.new server, numbers, connections, nil, json_output, method, body, headers, timeout_seconds, insecure, rate_limit
      end
    end

    # Prepares OptionParser
    private def prepare_op
      @options[:connections] = 10
      @options[:method] = "GET"
      @options[:headers] = [] of String
      begin
        OptionParser.parse(ARGV) do |opts|
          opts.banner = "Usage: cryload <url> [options]"

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

          opts.on("-H HEADER", "--header HEADER", "HTTP header, repeatable (e.g. -H 'Authorization: Bearer token')") do |v|
            headers = @options[:headers].as(Array(String))
            headers << v
          end

          opts.on("--timeout SECONDS", "Client connect/read timeout in seconds") do |v|
            @options[:timeout] = v.to_i
          end

          opts.on("-q RATE", "--rate RATE", "Total request rate limit in requests/sec") do |v|
            @options[:rate] = v.to_i
          end

          opts.on("--insecure", "Accept invalid TLS certificates (HTTPS only)") do
            @options[:insecure] = true
          end

          opts.on("--json", "Output final results as JSON") do
            @options[:json] = true
          end

          opts.on("-h", "--help", "Print Help") do
            puts opts
            @show_help = true
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
      unless @options.has_key?(:server)
        STDERR.puts "Usage: cryload <url> [options]".colorize(:red)
        STDERR.puts "Example: cryload http://localhost:3000 -n 100".colorize(:red)
        return false
      end

      server = @options[:server].as(String)
      unless valid_url?(server)
        STDERR.puts "Invalid URL '#{server}'. Use an absolute http(s) URL (e.g. http://localhost:3000).".colorize(:red)
        return false
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

      if @options.has_key?(:timeout)
        timeout = @options[:timeout].as(Int32)
        if timeout <= 0
          STDERR.puts "Timeout must be greater than 0 seconds.".colorize(:red)
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
      return if json_output?
      puts message.colorize(:green)
    end

    private def json_output?
      @options[:json]?.try(&.as(Bool)) || false
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

    private def valid_url?(url : String)
      uri = URI.parse(url)
      return false if uri.host.nil?
      uri.scheme == "http" || uri.scheme == "https"
    rescue URI::Error
      false
    end
  end
end
