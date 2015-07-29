require "./cryload/*"
require "http"

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
      channel = Channel(Int32).new
      spawn do
        loop do
          start_time = Time.now
          HTTP::Client.get @host
          end_time = Time.now
          time_taken_in_ms = (end_time - start_time).to_f * 1000.0
          @stats.add_to_request_times time_taken_in_ms
          channel.send 0
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
  p "You need to set a host!"
  exit
else
  host = ARGV.shift
  request_count = unless ARGV.empty?
    ARGV.shift
  else
    1000
  end
  p "Preparing to make it CRY for #{request_count} requests!"
  Cryload::LoadGenerator.new host, request_count.to_i
end
