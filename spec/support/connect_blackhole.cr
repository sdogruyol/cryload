require "socket"

# A listening port whose accept queue is full, so every further SYN is dropped
# and a client connect hangs until its own timeout fires. That is the only way
# to get a genuine connect timeout on loopback without depending on how the
# network treats a non-routable address.
module ConnectBlackhole
  def self.open(&)
    server = TCPServer.new("127.0.0.1", 0, backlog: 1)
    port = server.local_address.port
    fillers = [] of TCPSocket

    begin
      16.times do
        fillers << TCPSocket.new("127.0.0.1", port, connect_timeout: 100.milliseconds)
      rescue IO::TimeoutError
        break
      end
      raise "accept queue never filled; cannot simulate a connect timeout" if fillers.size == 16

      yield port
    ensure
      fillers.each(&.close)
      server.close
    end
  end
end
