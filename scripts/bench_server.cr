require "http/server"

server = HTTP::Server.new do |context|
  context.response.status_code = 200
  context.response.content_type = "text/plain"
  context.response.print "OK"
end

address = server.bind_tcp "127.0.0.1", 0
port = address.port
File.write("/tmp/cryload-bench-port", port.to_s)
spawn { server.listen }

sleep 0.2
STDERR.puts "bench-server listening on http://127.0.0.1:#{port}"

sleep
