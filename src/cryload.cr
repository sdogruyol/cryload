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
      end
    end

    def generate_request_channel()
      channel = Channel(Nil).new
      uri = URI.parse @host
      client = HTTP::Client.new uri.host.not_nil!, port: uri.port, ssl: uri.scheme == "https"
      spawn do
        loop do
          start_time = Time.now
          response = client.get uri.full_path
          end_time = Time.now
          request = Request.new start_time, end_time, response.status_code
          @stats.requests << request
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

Cryload::Cli.new
