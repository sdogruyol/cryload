# Command Line Interface Handler for Cryload
module Cryload
  class Cli
    def initialize
      @options = Hash(Symbol, (String | Bool)).new
      prepare_op
      if input_valid?
        Cryload::LoadGenerator.new(@options[:server].to_s, @options[:numbers].as(String).to_i, @options[:tls].as(Bool))
      end
    end

    # Prepares OptionParser
    private def prepare_op
      OptionParser.parse(ARGV) do |opts|
        opts.banner = "Usage: ./cryload [options]"

        opts.on("-s SERVER", "--server SERVER", "Target Server") do |v|
          @options[:server] = v
        end

        opts.on("-n NUMBERS", "--numbers NUMBERS", "Number of requests to make") do |v|
          @options[:numbers] = v
        end

        opts.on("-t SSL", "--tls SSL", "Verify remote SSL certificate ? [y/n]") do |v|
          @options[:tls] = (v.downcase == "y") ? true : false
        end

        opts.on("-h", "--help", "Print Help") do |v|
          puts opts
        end

        if ARGV.empty?
          puts opts
        end
      end.parse!
      unless @options.has_key?(:tls)
        @options[:tls] = false
      end
    end

    # Validate the input from command line
    private def input_valid?
      if @options.has_key?(:server) && @options.has_key?(:numbers)
        puts "Preparing to make it CRY for #{@options[:numbers]} requests!".colorize(:green)
        return true
      elsif @options.has_key?(:server)
        puts "You have to specify '-n' or '--numbers' flag to indicate the number of requests to make".colorize(:red)
        return false
      elsif @options.has_key?(:numbers)
        puts "You have to specify '-s' or '--server' flag to indicate the target server".colorize(:red)
        return false
      else
        puts "You have to specify '-n' and '-s' flags, for help use '-h'".colorize(:red)
        return false
      end
    end
  end
end
