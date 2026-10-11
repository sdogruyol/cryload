module Cryload
  # `HTTP::Client` that splits connection setup into DNS, TCP connect and TLS
  # handshake timings.
  #
  # `HTTP::Client` resolves and connects lazily inside its private `#io`, so
  # overriding that is the only place the three phases can be measured
  # separately without giving up automatic reconnection when a keep-alive
  # connection is dropped. Handing a pre-connected socket to
  # `HTTP::Client.new(io, ...)` would measure the phases just as well but marks
  # the client non-reconnectable, which turns every server-side keep-alive
  # timeout into a hard failure.
  class PhasedClient < HTTP::Client
    getter connections_opened : Int64
    getter last_dns_ms : Float64
    getter last_connect_ms : Float64
    # Nil when the last connection carried no TLS handshake, so a plain HTTP run
    # reports zero handshakes instead of a run of zero-millisecond ones.
    getter last_tls_ms : Float64?

    def initialize(host : String, port = nil, tls : HTTP::Client::TLSContext = nil)
      @connections_opened = 0_i64
      @last_dns_ms = 0.0
      @last_connect_ms = 0.0
      @last_tls_ms = nil
      super(host, port, tls)
    end

    # Adopts an already-established connection (the HTTPS-over-proxy CONNECT
    # tunnel) together with the phase timings measured while building it.
    def initialize(io : IO, host : String, port : Int32, dns_ms : Float64, connect_ms : Float64, tls_ms : Float64?)
      @connections_opened = 1_i64
      @last_dns_ms = dns_ms
      @last_connect_ms = connect_ms
      @last_tls_ms = tls_ms
      super(io, host, port)
    end

    private def io
      existing = @io
      return existing if existing
      raise "This HTTP::Client cannot be reconnected" unless @reconnect

      @io = connect_measured
    end

    private def connect_measured : IO
      hostname = @host.starts_with?('[') && @host.ends_with?(']') ? @host[1..-2] : @host

      dns_start = Time.instant
      addrinfos = Socket::Addrinfo.tcp(hostname, @port, timeout: @dns_timeout)
      dns_ms = Cryload.elapsed_ms(dns_start)

      connect_start = Time.instant
      socket = connect_any(addrinfos)
      connect_ms = Cryload.elapsed_ms(connect_start)

      socket.read_timeout = @read_timeout if @read_timeout
      socket.write_timeout = @write_timeout if @write_timeout
      socket.sync = false

      connection = socket.as(IO)
      tls_ms : Float64? = nil

      {% unless flag?(:without_openssl) %}
        if tls_context = @tls
          tls_start = Time.instant
          begin
            connection = OpenSSL::SSL::Socket::Client.new(
              socket, context: tls_context, sync_close: true, hostname: @host.rchop('.')
            )
          rescue ex
            socket.close
            raise ex
          end
          tls_ms = Cryload.elapsed_ms(tls_start)
        end
      {% end %}

      @last_dns_ms = dns_ms
      @last_connect_ms = connect_ms
      @last_tls_ms = tls_ms
      @connections_opened += 1
      connection
    end

    # Walks the resolved addresses so a host with a dead AAAA record still
    # connects over IPv4, matching `TCPSocket.new(host, port)`.
    private def connect_any(addrinfos : Array(Socket::Addrinfo)) : TCPSocket
      last_error = nil

      addrinfos.each do |addrinfo|
        socket = TCPSocket.new(addrinfo.family)
        begin
          socket.connect(addrinfo, timeout: @connect_timeout)
          return socket
        rescue ex : IO::TimeoutError
          socket.close
          last_error = ConnectTimeoutError.new("Connect to #{@host}:#{@port} timed out", cause: ex)
        rescue ex
          socket.close
          last_error = ex
        end
      end

      raise(last_error || Socket::Error.new("No usable address for #{@host}:#{@port}"))
    end
  end
end
