require "http/server"

module TestServer
  def self.start(&handler : HTTP::Server::Context ->)
    server = HTTP::Server.new(&handler)
    address = server.bind_unused_port
    spawn { server.listen }
    sleep 50.milliseconds
    {server, address.port}
  end
end
