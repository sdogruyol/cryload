require "./cryload/*"
require "http"
require "colorize"

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

if ARGV.empty?
  puts "You need to set a host!".colorize(:red)
  exit
else
  host = ARGV.shift
  request_count = unless ARGV.empty?
    ARGV.shift
  else
    1000
  end
  puts "Preparing to make it CRY for #{request_count} requests!".colorize(:green)
  Cryload::LoadGenerator.new host, request_count.to_i
end
