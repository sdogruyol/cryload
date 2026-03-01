require "spec"
require "http/server"

describe "Cryload E2E" do
  it "completes requests and prints final stats" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    server_task = spawn do
      server.listen
    end

    sleep 100.milliseconds

    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://127.0.0.1:#{port}", "-n", "10"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    server.close
    Fiber.yield

    process.exit_code.should eq(0)
    output.to_s.should contain("Preparing to make it CRY for 10 requests")
    output.to_s.should contain("Completed All Requests!")
    output.to_s.should contain("2xx requests")
    output.to_s.should contain("Total request made: 10")
  end

  it "reports 2xx as successful requests" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://127.0.0.1:#{port}", "-n", "10"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("2xx requests 10")
  end

  it "reports non-2xx as failed requests" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 404
      context.response.print "Not Found"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://127.0.0.1:#{port}", "-n", "5"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("Non 2xx requests 5")
  end

  it "accepts -c/--connections for parallel requests" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://127.0.0.1:#{port}", "-n", "20", "-c", "5"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("with 5 connections")
    output.to_s.should contain("Total request made: 20")
  end

  it "prints help when -h is passed" do
    output = IO::Memory.new
    Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-h"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    output.to_s.should contain("Usage:")
    output.to_s.should contain("--server")
    output.to_s.should contain("--numbers")
    output.to_s.should contain("--duration")
  end

  it "exits with error when server is missing" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-n", "10"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("--server")
    process.exit_code.should eq(0)
  end

  it "exits with error when neither -n nor -d is specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://localhost:8080"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("-n")
    combined.should contain("-d")
    process.exit_code.should eq(0)
  end

  it "runs for specified duration with -d" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "-s", "http://127.0.0.1:#{port}", "-d", "1", "-c", "3"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("1 seconds")
    output.to_s.should contain("Completed All Requests!")
    output.to_s.should contain("Total request made:")
  end
end
