require "./cryload/*"
require "http"

module Cryload
  class LoadGenerator
    def initialize(@host, @number=1000)
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
        p "Average time taken per request: #{@stats.average_request_time} ms"
        p "Total request made: #{@stats.total_request_count}"
        exit
      end
    end
  end
end

Cryload::LoadGenerator.new ARGV[0]
