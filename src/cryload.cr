require "./cryload/*"
require "http"
require "colorize"
require "option_parser"

module Cryload
  class LoadGenerator
    def initialize(@host, @number)
      @stats = Stats.new @number
      ch = generate_request_channel
      loop do
        check_log
        ch.receive
        @stats.increase_total_request_count
      end
    end

    def generate_request_channel()
      channel = Channel(Nil).new
      uri = URI.parse @host
      full_path = uri.full_path
      client = HTTP::Client.new uri.host.not_nil!, port: uri.port
      spawn do
        loop do
          start_time = Time.now
          client.get full_path
          end_time = Time.now
          time_taken_in_ms = (end_time - start_time).to_f * 1000.0
          @stats.add_to_request_times time_taken_in_ms
          channel.send nil
        end
      end
      channel
    end

    def check_log
      Logger.new @stats
    end
  end
end

options = {} of Symbol => String
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  
  opts.on("-s", "--server", "Target Server") do |v|
    options[:server] = v
  end

  opts.on("-r", "--requests", "Number of requests to make") do |v|
    options[:requests] = v
  end

  opts.on("-h", "--help", "Print Help") do |v|
    puts opts
  end

  if ARGV.empty?
    puts opts
  end
end.parse!


if options.has_key?(:server) && options.has_key?(:requests)
  puts "Preparing to make it CRY for #{options[:requests]} requests!".colorize(:green)
  Cryload::LoadGenerator.new options[:server], options[:requests].to_i
end
