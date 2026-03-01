require "./cryload/*"
require "http"
require "colorize"
require "option_parser"

module Cryload
  # LoadGenerator is the main class in Cryload. It's responsible for generating
  # the requests and other major stuff.
  class LoadGenerator
    @@connection_error_printed = false
    @@connection_error_mutex = Mutex.new

    # LoadGenerator: request mode (host, request_number, connections) or duration mode (host, connections, duration_seconds).
    def initialize(@host : String, request_number : Int32? = nil, @connections : Int32 = 10, duration_seconds : Int32? = nil)
      @request_number = request_number || -1
      @duration_seconds = duration_seconds
      @duration_mode = !@duration_seconds.nil?

      Cryload.create_stats @request_number, @duration_mode, Time.instant
      request_channel, done_channel, worker_count = generate_request_channel
      spawn_receive_loop request_channel, done_channel, worker_count
    end

    # Generates request and done channels. Spawns workers (request count or duration based).
    def generate_request_channel
      request_channel = Channel(Nil).new
      done_channel = Channel(Nil).new
      uri = parse_uri
      worker_count = @duration_mode ? {1, @connections}.max : {1, {@connections, @request_number}.min}.max

      worker_count.times do |i|
        if @duration_mode
          spawn_duration_worker request_channel, done_channel, uri
        else
          spawn_request_worker request_channel, uri, i, worker_count
        end
      end

      {request_channel, done_channel, worker_count}
    end

    # Spawns a worker that runs for duration_seconds, making requests until time is up.
    def spawn_duration_worker(request_channel, done_channel, uri)
      spawn do
        client = create_http_client uri
        deadline = Time.instant + @duration_seconds.not_nil!.seconds

        while Time.instant < deadline
          create_request(client, uri)
          request_channel.send nil
        end

        done_channel.send nil
      end
    end

    # Spawns a worker that makes its share of requests.
    def spawn_request_worker(request_channel, uri, worker_index, total_workers)
      spawn do
        client = create_http_client uri
        requests_for_this_worker = requests_per_worker worker_index, total_workers

        requests_for_this_worker.times do
          create_request(client, uri)
          request_channel.send nil
        end
      end
    end

    # Distributes requests across workers. First (request_number % workers) get one extra.
    private def requests_per_worker(worker_index, total_workers)
      base = @request_number // total_workers
      remainder = @request_number % total_workers
      worker_index < remainder ? base + 1 : base
    end

    # Spawns the receiver loop. In request mode: receive until count reached.
    # In duration mode: use select to receive requests and worker-done signals.
    def spawn_receive_loop(request_channel, done_channel, worker_count)
      if @duration_mode
        spawn_receive_loop_duration request_channel, done_channel, worker_count
      else
        spawn_receive_loop_requests request_channel
      end
    end

    def spawn_receive_loop_requests(request_channel)
      loop do
        ExecutionHandler.check
        request_channel.receive
      end
    end

    def spawn_receive_loop_duration(request_channel, done_channel, worker_count)
      done_count = 0

      loop do
        select
        when request_channel.receive
          ExecutionHandler.check_duration
        when done_channel.receive
          done_count += 1
          break if done_count >= worker_count
        end
      end

      Logger.log_final
      exit
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
    rescue ex : Socket::Error | IO::Error | OpenSSL::SSL::Error
      host = uri.host || "localhost"
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      msg = ex.message.to_s
      @@connection_error_mutex.synchronize do
        unless @@connection_error_printed
          STDERR.puts "Connection failed: Could not reach #{host}:#{port}"
          STDERR.puts "  → #{msg}"
          STDERR.puts "  → Check if the server is running and accepting connections on this port."
          @@connection_error_printed = true
        end
      end
      exit 1
    end
  end
end
