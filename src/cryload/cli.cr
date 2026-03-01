# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = {} of Symbol => String | Int32
      prepare_op
      if input_valid?
        connections = @options[:connections].as(Int32)
        server = @options[:server].as(String)
        if @options.has_key?(:duration)
          duration = @options[:duration].as(Int32)
          Cryload::LoadGenerator.new server, nil, connections, duration
        else
          numbers = @options[:numbers].to_s.to_i
          Cryload::LoadGenerator.new server, numbers, connections
        end
      end
    end

    # Prepares OptionParser
    private def prepare_op
      @options[:requests] = "1000"
      @options[:connections] = 10
      OptionParser.parse(ARGV) do |opts|
        opts.banner = "Usage: ./cryload [options]"

        opts.on("-s SERVER", "--server SERVER", "Target Server") do |v|
          @options[:server] = v
        end

        opts.on("-n NUMBERS", "--numbers NUMBERS", "Number of requests to make") do |v|
          @options[:numbers] = v
        end

        opts.on("-c CONNECTIONS", "--connections CONNECTIONS", "Number of concurrent connections (default: 10)") do |v|
          @options[:connections] = v.to_i
        end

        opts.on("-d SECONDS", "--duration SECONDS", "Duration of test in seconds (e.g. -d 10 for 10 seconds)") do |v|
          @options[:duration] = v.to_i
        end

        opts.on("-h", "--help", "Print Help") do |v|
          puts opts
        end

        if ARGV.empty?
          puts opts
        end
      end.parse
    end

    # Validate the input from command line
    private def input_valid?
      unless @options.has_key?(:server)
        puts "You have to specify '-s' or '--server' flag to indicate the target server".colorize(:red)
        return false
      end

      if @options.has_key?(:duration)
        puts "Preparing to make it CRY for #{@options[:duration]} seconds with #{@options[:connections]} connections!".colorize(:green)
        true
      elsif @options.has_key?(:numbers)
        puts "Preparing to make it CRY for #{@options[:numbers]} requests with #{@options[:connections]} connections!".colorize(:green)
        true
      else
        puts "You have to specify '-n' (number of requests) or '-d' (duration in seconds)".colorize(:red)
        false
      end
    end
  end
end
