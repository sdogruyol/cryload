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
  # timeout into a hard failure. That is also why the HTTPS-over-proxy CONNECT
  # tunnel is opened here rather than by the caller.
  class PhasedClient < HTTP::Client
    # An HTTP(S) proxy that the connection to the target is tunnelled through
    # with CONNECT. `tls` is the context for the proxy hop itself (an
    # `https://` proxy), nil for a plain-HTTP proxy.
    record Tunnel, proxy : URI, tls : OpenSSL::SSL::Context::Client?

    getter connections_opened : Int64
    getter last_dns_ms : Float64
    getter last_connect_ms : Float64
    # Nil when the last connection carried no TLS handshake, so a plain HTTP run
    # reports zero handshakes instead of a run of zero-millisecond ones.
    getter last_tls_ms : Float64?

    def initialize(host : String, port = nil, tls : HTTP::Client::TLSContext = nil, @tunnel : Tunnel? = nil)
      @connections_opened = 0_i64
      @last_dns_ms = 0.0
      @last_connect_ms = 0.0
      @last_tls_ms = nil
      super(host, port, tls)

      # The stdlib's implicit compression advertises gzip and then inflates the
      # body, so Transfer counted decompressed bytes and the generator spent CPU
      # on zlib for bodies it discards. Sending the same header itself keeps the
      # target's behaviour unchanged while the body stays as it came off the
      # wire. An explicit -H Accept-Encoding wins.
      self.compress = false
      before_request { |request| request.headers["Accept-Encoding"] ||= "gzip, deflate" }
    end

    private def io
      existing = @io
      return existing if existing
      raise "This HTTP::Client cannot be reconnected" unless @reconnect

      @io = connect_measured
    end

    # Through a tunnel, `dns` and `connect` describe the hop to the proxy and
    # `connect` also covers the proxy's TLS handshake and the CONNECT exchange;
    # `tls` is the end-to-end handshake with the target.
    private def connect_measured : IO
      if tunnel = @tunnel
        dial_host = tunnel.proxy.hostname || raise ArgumentError.new("Proxy host is required")
        dial_port = Cryload.effective_port(tunnel.proxy)
      else
        dial_host = @host.starts_with?('[') && @host.ends_with?(']') ? @host[1..-2] : @host
        dial_port = @port
      end

      dns_start = Time.instant
      addrinfos = Socket::Addrinfo.tcp(dial_host, dial_port, timeout: @dns_timeout)
      dns_ms = Cryload.elapsed_ms(dns_start)

      connect_start = Time.instant
      socket = connect_any(addrinfos, dial_host, dial_port)

      connection = socket.as(IO)
      tls_ms : Float64? = nil
      begin
        socket.read_timeout = @read_timeout if @read_timeout
        socket.write_timeout = @write_timeout if @write_timeout
        socket.sync = false

        connection = open_tunnel(socket, tunnel, dial_host) if tunnel
        connect_ms = Cryload.elapsed_ms(connect_start)

        if tls_context = @tls
          tls_start = Time.instant
          connection = OpenSSL::SSL::Socket::Client.new(
            connection, context: tls_context, sync_close: true, hostname: @host.rchop('.')
          )
          tls_ms = Cryload.elapsed_ms(tls_start)
        end
      rescue ex
        # Closing the raw socket releases the fd whichever layer failed; the
        # TLS wrappers around it hold no descriptor of their own.
        socket.close
        raise ex
      end

      @last_dns_ms = dns_ms
      @last_connect_ms = connect_ms
      @last_tls_ms = tls_ms
      @connections_opened += 1
      connection
    end

    private def open_tunnel(socket : TCPSocket, tunnel : Tunnel, proxy_host : String) : IO
      hop = socket.as(IO)
      if proxy_tls = tunnel.tls
        hop = OpenSSL::SSL::Socket::Client.new(socket, context: proxy_tls, sync_close: true, hostname: proxy_host)
      end

      hop << Cryload.connect_request(@host, @port, tunnel.proxy)
      hop.flush

      status_code = Cryload.read_proxy_connect_status(hop)
      raise IO::Error.new("Proxy CONNECT failed with status #{status_code}") unless status_code == 200
      hop
    end

    # Walks the resolved addresses so a host with a dead AAAA record still
    # connects over IPv4, matching `TCPSocket.new(host, port)`.
    private def connect_any(addrinfos : Array(Socket::Addrinfo), host : String, port : Int32) : TCPSocket
      last_error = nil

      addrinfos.each do |addrinfo|
        socket = TCPSocket.new(addrinfo.family)
        begin
          socket.connect(addrinfo, timeout: @connect_timeout)
          return socket
        rescue ex : IO::TimeoutError
          socket.close
          last_error = ConnectTimeoutError.new("Connect to #{host}:#{port} timed out", cause: ex)
        rescue ex
          socket.close
          last_error = ex
        end
      end

      raise(last_error || Socket::Error.new("No usable address for #{host}:#{port}"))
    end
  end
end
