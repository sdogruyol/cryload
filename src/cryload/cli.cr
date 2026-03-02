# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = {} of Symbol => String | Int32
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
      if @options.has_key?(:duration)
        duration = @options[:duration].as(Int32)
        Cryload::LoadGenerator.new server, nil, connections, duration
      else
        numbers = @options[:numbers].as(Int32)
        Cryload::LoadGenerator.new server, numbers, connections
      end
    end

    # Prepares OptionParser
    private def prepare_op
      @options[:connections] = 10
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
        puts "Preparing to make it CRY for #{@options[:duration]} seconds with #{@options[:connections]} connections!".colorize(:green)
        true
      elsif @options.has_key?(:numbers)
        numbers = @options[:numbers].as(Int32)
        if numbers <= 0
          STDERR.puts "Number of requests must be greater than 0.".colorize(:red)
          return false
        end
        puts "Preparing to make it CRY for #{@options[:numbers]} requests with #{@options[:connections]} connections!".colorize(:green)
        true
      else
        STDERR.puts "You have to specify '-n' (number of requests) or '-d' (duration in seconds)".colorize(:red)
        false
      end
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
