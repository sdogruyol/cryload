require "spec"
require "http/server"
require "json"

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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "10"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    server.close
    Fiber.yield

    process.exit_code.should eq(0)
    output.to_s.should contain("Preparing to make it CRY for 10 requests")
    output.to_s.should contain("2xx:")
    output.to_s.should contain("requests in")
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "10"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("2xx: 10")
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "5"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("Non-2xx: 5")
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "20", "-c", "5"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("Running load test @")
    output.to_s.should contain("20 requests in")
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
    output.to_s.should contain("<url>")
    output.to_s.should contain("--numbers")
    output.to_s.should contain("--duration")
    output.to_s.should contain("--json")
    output.to_s.should contain("--method")
    output.to_s.should contain("--body")
    output.to_s.should contain("--header")
    output.to_s.should contain("--timeout")
  end

  it "exits with error when url is missing" do
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
    combined.should contain("cryload <url>")
    process.exit_code.should eq(1)
  end

  it "exits with error when neither -n nor -d is specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("-n")
    combined.should contain("-d")
    process.exit_code.should eq(1)
  end

  it "exits with error when url is invalid" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "localhost:8080", "-n", "10"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid URL")
    process.exit_code.should eq(1)
  end

  it "shows connection refused error when server is unreachable" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:19999", "-n", "5"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Connection failed")
    combined.should contain("Could not reach")
    process.exit_code.should eq(1)
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-d", "1", "-c", "3"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    output.to_s.should contain("Preparing to make it CRY for 1 seconds")
    output.to_s.should contain("requests in")
  end

  it "supports custom method, header and body" do
    server = HTTP::Server.new do |context|
      if context.request.method == "POST" &&
         context.request.headers["X-Cryload-Test"]? == "ok" &&
         context.request.body.try(&.gets_to_end) == "hello"
        context.response.status_code = 200
        context.response.print "OK"
      else
        context.response.status_code = 400
        context.response.print "BAD"
      end
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "5", "-m", "POST", "-H", "X-Cryload-Test: ok", "-b", "hello"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("2xx: 5")
  end

  it "exits with error on invalid header format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "-H", "InvalidHeader"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid header format")
    process.exit_code.should eq(1)
  end

  it "outputs json with --json including p95 and p99" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "20", "--json"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["requests"].as_i.should eq(20)
    parsed["latency_ms"]["p95"].as_f.should be >= 0.0
    parsed["latency_ms"]["p99"].as_f.should be >= 0.0
    parsed["status_counts"]["2xx"].as_i.should eq(20)
  end
end
