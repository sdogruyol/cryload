require "./cryload/*"
require "http"

module Cryload
  class LoadGenerator
    def initialize(@host)
      @request_count = 0
      ch = generate_request_channel
      loop do
        ch.receive
        p "Total request made: #{@request_count}"
      end
    end

    def generate_request_channel()
      channel = Channel(Int32).new
      spawn do
        loop do
          HTTP::Client.get @host
          @request_count+= 1
          channel.send @request_count
        end
      end
      channel
    end
  end
end

Cryload::LoadGenerator.new ARGV[0]
