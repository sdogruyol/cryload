require "./cryload/*"
require "http"
require "colorize"
require "option_parser"

module Cryload
  # LoadGenerator is the main class in Cryload. It's responsible for generating
  # the requests and other major stuff.
  class LoadGenerator
    # LoadGenerator accepts host, request_number and connections (concurrent fibers).
    def initialize(@host : String, @request_number : Int32, @connections : Int32 = 10)
      Cryload.create_stats @request_number
      channel = generate_request_channel
      spawn_receive_loop channel
    end

    # Generates a Channel for asynchronously sending HTTP requests.
    # Spawns multiple workers (connections) that run in parallel.
    def generate_request_channel
      channel = Channel(Nil).new
      uri = parse_uri
      connections = {1, {@connections, @request_number}.min}.max

      connections.times do |i|
        spawn_request_worker channel, uri, i, connections
      end

      channel
    end

    # Spawns a worker that makes its share of requests.
    # Each worker has its own HTTP client for connection reuse.
    def spawn_request_worker(channel, uri, worker_index, total_workers)
      spawn do
        client = create_http_client uri
        requests_for_this_worker = requests_per_worker worker_index, total_workers

        requests_for_this_worker.times do
          create_request(client, uri)
          channel.send nil
        end
      end
    end

    # Distributes requests across workers. First (request_number % workers) get one extra.
    private def requests_per_worker(worker_index, total_workers)
      base = @request_number // total_workers
      remainder = @request_number % total_workers
      worker_index < remainder ? base + 1 : base
    end

    # Spawns the receiver loop which listens the send events from channel.
    # This loop is also responsible for checking the logs and gathering stats
    # about all the completed requests.
    def spawn_receive_loop(channel)
      loop do
        ExecutionHandler.check
        channel.receive
      end
    end

    # Parses the host string and converts it to an URI
    private def parse_uri
      uri = URI.parse @host
    end

    # Creates the HTTP client
    private def create_http_client(uri)
      HTTP::Client.new uri.host.not_nil!, port: uri.port, tls: uri.scheme == "https"
    end

    # Creates a new request to the given URI
    private def create_request(client, uri)
      request = Request.new client, uri
      Cryload.stats << request
    end
  end
end
