require "./spec_helper"
require "http/client"
require "http/server"

describe Cryload do
  it "generates load on server" do
    server = create_server
    Cryload::LoadGenerator.new "http://localhost:8081", 10
    server.close
  end
end
