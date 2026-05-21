require "./spec_helper"
require "./support/test_server"

module RequestSpecHelper
  def self.perform_request(port, path, method = "GET", body : String? = nil, follow_redirects = false)
    uri = URI.parse("http://127.0.0.1:#{port}#{path}")
    client = Cryload.create_http_client(uri)
    begin
      Cryload::Request.new client, uri, method, HTTP::Headers.new, body, follow_redirects: follow_redirects
    ensure
      client.close
    end
  end
end

describe Cryload::Request do
  it "resolves relative redirect paths with parent segments" do
    seen_paths = [] of String
    server, port = TestServer.start do |context|
      seen_paths << context.request.path
      case context.request.path
      when "/api/v1/start"
        context.response.status_code = 302
        context.response.headers["Location"] = "../v2/final"
      else
        context.response.status_code = 200
        context.response.print "OK"
      end
    end

    request = RequestSpecHelper.perform_request(port, "/api/v1/start", follow_redirects: true)
    server.close

    request.status_code.should eq(200)
    seen_paths.should contain("/api/v2/final")
  end

  it "resolves sibling relative redirect paths" do
    seen_paths = [] of String
    server, port = TestServer.start do |context|
      seen_paths << context.request.path
      case context.request.path
      when "/files/current/doc"
        context.response.status_code = 302
        context.response.headers["Location"] = "other.txt"
      else
        context.response.status_code = 200
        context.response.print "OK"
      end
    end

    request = RequestSpecHelper.perform_request(port, "/files/current/doc", follow_redirects: true)
    server.close

    request.status_code.should eq(200)
    seen_paths.should contain("/files/current/other.txt")
  end

  it "converts POST to GET after a 302 redirect" do
    methods = [] of String
    server, port = TestServer.start do |context|
      methods << context.request.method
      case context.request.path
      when "/post"
        context.response.status_code = 302
        context.response.headers["Location"] = "/target"
      else
        context.response.status_code = 200
        context.response.print context.request.method
      end
    end

    request = RequestSpecHelper.perform_request(port, "/post", "POST", "payload", follow_redirects: true)
    server.close

    request.status_code.should eq(200)
    methods.should eq(["POST", "GET"])
  end

  it "stops following redirects after the configured maximum" do
    server, port = TestServer.start do |context|
      hop = (context.request.query || "n=0").split("=").last.to_i
      if hop < Cryload::DEFAULT_MAX_REDIRECTS + 1
        context.response.status_code = 302
        context.response.headers["Location"] = "/hop?n=#{hop + 1}"
      else
        context.response.status_code = 200
        context.response.print "done"
      end
    end

    request = RequestSpecHelper.perform_request(port, "/hop?n=0", follow_redirects: true)
    server.close

    request.status_code.should eq(302)
  end

  it "follows absolute redirect locations on the same host" do
    seen_paths = [] of String
    redirect_port = 0
    server = HTTP::Server.new do |context|
      seen_paths << context.request.path
      case context.request.path
      when "/start"
        context.response.status_code = 307
        context.response.headers["Location"] = "http://127.0.0.1:#{redirect_port}/absolute"
      else
        context.response.status_code = 200
        context.response.print "OK"
      end
    end
    address = server.bind_unused_port
    redirect_port = address.port
    spawn { server.listen }
    sleep 50.milliseconds

    request = RequestSpecHelper.perform_request(redirect_port, "/start", follow_redirects: true)
    server.close

    request.status_code.should eq(200)
    seen_paths.should contain("/absolute")
  end
end
