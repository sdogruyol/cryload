require "spec"
require "http/server"
require "json"

describe "Cryload E2E" do
  fixture_body_file = File.join(File.dirname(__DIR__), "spec", "support", "request-body.json")

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
    output.to_s.should contain("Successful:")
    output.to_s.should contain("min:")
    output.to_s.should contain("requests in")
  end

  it "reports successful requests" do
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

    output.to_s.should contain("Successful: 10")
  end

  it "reports failed requests" do
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

    output.to_s.should contain("Failed: 5")
    output.to_s.should contain("Status codes: 404: 5")
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
    output.to_s.should contain("--body-file")
    output.to_s.should contain("--header")
    output.to_s.should contain("--user-agent")
    output.to_s.should contain("--host-header")
    output.to_s.should contain("--basic-auth")
    output.to_s.should contain("--timeout")
    output.to_s.should contain("--rate")
    output.to_s.should contain("--follow-redirects")
    output.to_s.should contain("--output-format")
    output.to_s.should contain("--success-status")
    output.to_s.should contain("--insecure")
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
    combined.should contain("Continuing and counting transport errors")
    output.to_s.should contain("Errors: 5")
    output.to_s.should contain("Transport errors: Socket::ConnectError: 5")
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
    output.to_s.should contain("Successful: 5")
  end

  it "supports body-file and basic auth" do
    expected_body = File.read(fixture_body_file)

    server = HTTP::Server.new do |context|
      auth_header = context.request.headers["Authorization"]?
      content_type = context.request.headers["Content-Type"]?
      body = context.request.body.try(&.gets_to_end)

      if context.request.method == "POST" &&
         auth_header == "Basic dXNlcjpzZWNyZXQ=" &&
         content_type == "application/json" &&
         body == expected_body
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "3", "-m", "POST", "--body-file", fixture_body_file, "--basic-auth", "user:secret", "-H", "Content-Type: application/json"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
  end

  it "supports user-agent and host-header convenience flags" do
    server = HTTP::Server.new do |context|
      if context.request.headers["User-Agent"]? == "cryload-test/1.0" &&
         context.request.headers["Host"]? == "bench.local"
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "3", "--user-agent", "cryload-test/1.0", "--host-header", "bench.local"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
  end

  it "does not follow redirects by default" do
    server = HTTP::Server.new do |context|
      if context.request.path == "/redirect"
        context.response.status_code = 302
        context.response.headers["Location"] = "/final"
      else
        context.response.status_code = 200
        context.response.print "OK"
      end
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}/redirect", "-n", "3"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 0")
    output.to_s.should contain("Failed: 3")
    output.to_s.should contain("Status codes: 302: 3")
  end

  it "follows redirects with --follow-redirects" do
    server = HTTP::Server.new do |context|
      if context.request.path == "/redirect"
        context.response.status_code = 302
        context.response.headers["Location"] = "/final"
      else
        context.response.status_code = 200
        context.response.print "OK"
      end
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}/redirect", "-n", "3", "--follow-redirects"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
    output.to_s.should contain("Failed: 0")
    output.to_s.should contain("Status codes: 200: 3")
  end

  it "supports custom success statuses" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 302
      context.response.headers["Location"] = "/another"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}/redirect", "-n", "3", "--success-status", "200-299,302"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
    output.to_s.should contain("Failed: 0")
    output.to_s.should contain("Success statuses: 200-299, 302")
  end

  it "exits with error on invalid success status format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--success-status", "abc"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid success status")
    process.exit_code.should eq(1)
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

  it "exits with error when body and body-file are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--body", "inline", "--body-file", fixture_body_file],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one body source")
    process.exit_code.should eq(1)
  end

  it "exits with error on invalid basic auth format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--basic-auth", "invalid"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid basic auth format")
    process.exit_code.should eq(1)
  end

  it "exits with error when basic auth and authorization header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--basic-auth", "user:secret", "-H", "Authorization: Bearer token"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one authorization source")
    process.exit_code.should eq(1)
  end

  it "exits with error when user-agent flag and User-Agent header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--user-agent", "cryload-test/1.0", "-H", "User-Agent: other"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one User-Agent source")
    process.exit_code.should eq(1)
  end

  it "exits with error when host-header flag and Host header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--host-header", "bench.local", "-H", "Host: other.local"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one Host header source")
    process.exit_code.should eq(1)
  end

  it "exits with error on invalid http method" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "-m", "FOO"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid HTTP method")
    process.exit_code.should eq(1)
  end

  it "exits with error on non-positive timeout" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--timeout", "0"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Timeout must be greater than 0 seconds")
    process.exit_code.should eq(1)
  end

  it "exits with error on non-positive rate" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--rate", "0"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Rate must be greater than 0 requests/sec")
    process.exit_code.should eq(1)
  end

  it "exits with error on invalid output format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--output-format", "xml"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Invalid output format")
    process.exit_code.should eq(1)
  end

  it "exits with error when --json conflicts with another output format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://localhost:8080", "-n", "5", "--json", "--output-format", "csv"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one JSON output source")
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
    parsed["responses"].as_i.should eq(20)
    parsed["transport_errors"].as_i.should eq(0)
    parsed["latency_ms"]["min"].as_f.should be >= 0.0
    parsed["latency_ms"]["p50"].as_f.should be >= 0.0
    parsed["latency_ms"]["p90"].as_f.should be >= 0.0
    parsed["latency_ms"]["p95"].as_f.should be >= 0.0
    parsed["latency_ms"]["p99"].as_f.should be >= 0.0
    parsed["latency_ms"]["p999"].as_f.should be >= 0.0
    parsed["status_counts"]["successful"].as_i.should eq(20)
    parsed["status_counts"]["successful_percent"].as_f.should eq(100.0)
    parsed["status_counts"]["failed"].as_i.should eq(0)
    parsed["status_counts"]["failed_percent"].as_f.should eq(0.0)
    parsed["success_statuses"][0].as_s.should eq("200-299")
    parsed["response_status_codes"]["200"].as_i.should eq(20)
    parsed["transport_error_percent"].as_f.should eq(0.0)
  end

  it "outputs csv with --output-format csv" do
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "5", "--output-format", "csv"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    lines = output.to_s.lines.map(&.strip).reject(&.empty?)
    lines.size.should eq(2)
    lines[0].should contain("url,duration_mode,requests,responses,transport_errors,elapsed_seconds,requests_per_second,latency_avg_ms,latency_min_ms")
    lines[1].should contain("false,5,5,0")
  end

  it "suppresses final output with --output-format quiet" do
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "5", "--output-format", "quiet"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should eq("")
  end

  it "rate limits request mode with --rate" do
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-n", "6", "-c", "6", "--rate", "3", "--json"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["requests"].as_i.should eq(6)
    parsed["responses"].as_i.should eq(6)
    parsed["elapsed_seconds"].as_f.should be >= 1.5
    parsed["elapsed_seconds"].as_f.should be < 2.4
    parsed["requests_per_second"].as_f.should be >= 2.5
  end

  it "keeps duration mode close to target time with --rate" do
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
      ["run", "src/main.cr", "--", "http://127.0.0.1:#{port}", "-d", "2", "-c", "20", "--rate", "20", "--json"],
      output: output,
      chdir: File.dirname(__DIR__)
    )

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["elapsed_seconds"].as_f.should be < 2.3
    parsed["requests"].as_i.should be >= 38
    parsed["requests_per_second"].as_f.should be >= 18.0
  end

  it "outputs transport errors in json when target is unreachable" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(
      "crystal",
      ["run", "src/main.cr", "--", "http://127.0.0.1:19999", "-n", "3", "--json"],
      output: output,
      error: error,
      chdir: File.dirname(__DIR__)
    )

    process.exit_code.should eq(1)
    parsed = JSON.parse(output.to_s)
    parsed["requests"].as_i.should eq(3)
    parsed["responses"].as_i.should eq(0)
    parsed["transport_errors"].as_i.should eq(3)
    parsed["transport_error_percent"].as_f.should eq(100.0)
    parsed["error_counts"]["Socket::ConnectError"].as_i.should eq(3)
  end
end
