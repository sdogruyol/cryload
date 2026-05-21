module MockProxy
  def self.start
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.as(Socket::IPAddress).port
    request_lines = [] of String
    lines_mutex = Mutex.new

    spawn do
      loop do
        socket = server.accept
        spawn handle_client(socket, request_lines, lines_mutex)
      rescue IO::Error
        break
      end
    end

    sleep 20.milliseconds
    {server, port, request_lines, lines_mutex}
  end

  def self.handle_client(socket : Socket, request_lines : Array(String), lines_mutex : Mutex)
    request_line = socket.gets
    return unless request_line

    lines_mutex.synchronize { request_lines << request_line.strip }

    while (line = socket.gets)
      break if line == "\r\n" || line.strip.empty?
    end

    socket << "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
  ensure
    socket.close
  end
end
