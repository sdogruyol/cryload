require "socket"
require "openssl"

# A CONNECT proxy that really tunnels: it dials the requested authority and
# pipes bytes both ways until either side closes. With `tls` it is an
# `https://` proxy; with `respond: false` it reads the CONNECT request and then
# never answers, to exercise the client's read timeout.
module MockTunnelProxy
  def self.start(tls : OpenSSL::SSL::Context::Server? = nil, respond : Bool = true)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    lines = [] of String
    lines_mutex = Mutex.new

    spawn do
      loop do
        socket = server.accept
        spawn handle(socket, tls, respond, lines, lines_mutex)
      rescue IO::Error
        break
      end
    end

    {server, port, lines, lines_mutex}
  end

  def self.handle(socket : TCPSocket, tls, respond : Bool, lines : Array(String), lines_mutex : Mutex)
    client = socket.as(IO)
    if tls
      # SSL sockets buffer writes and IO.copy never flushes, so the target's
      # bytes would sit in the buffer and the tunnel would stall.
      ssl = OpenSSL::SSL::Socket::Server.new(socket, tls, sync_close: true)
      ssl.sync = true
      client = ssl
    end
    request_line = client.gets
    return unless request_line

    head = [request_line.strip]
    while line = client.gets
      break if line.strip.empty?
      head << line.strip
    end
    lines_mutex.synchronize { lines.concat head }

    unless respond
      # Hold the connection until the client gives up and closes it.
      client.read(Bytes.new(1))
      return
    end

    authority = request_line.split[1]
    host, _, port = authority.rpartition(':')
    upstream = TCPSocket.new(host.strip('[').strip(']'), port.to_i)
    client << "HTTP/1.1 200 Connection established\r\n\r\n"
    client.flush

    spawn do
      IO.copy(upstream, client)
    rescue IO::Error
    ensure
      client.close
    end

    begin
      IO.copy(client, upstream)
    rescue IO::Error
    ensure
      upstream.close
    end
  rescue IO::Error | OpenSSL::SSL::Error
  ensure
    socket.close
  end
end
