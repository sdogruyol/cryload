require "spec"
require "../src/cryload"

def create_server
  server = HTTP::Server.new(8081) do |req|
    HTTP::Response.ok("text/plain", "OK")
  end
  spawn do
    server.listen
  end
  server
end
