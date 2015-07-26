require "./cryload/*"
require "http"

module Cryload
  class LoadGenerator
    def initialize(@host, @number)
      @stats = Stats.new
      ch = generate_request_channel
      loop do
        check
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

    def check
      if @stats.total_request_count == @number
        p "Average time taken per request: #{@stats.average_request_time.round(3)} ms"
        p "Request per second: #{@stats.request_per_second}"
        p "Total request made: #{@stats.total_request_count}"
        p "Total time taken: #{@stats.total_request_time_in_seconds} seconds"
        exit
      end
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
