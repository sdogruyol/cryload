require "./spec_helper"
require "./support/test_tls"
require "./support/mock_proxy"
require "./support/connect_blackhole"
require "./support/test_server"
require "http/server"
require "json"
require "csv"

# Helpers for the end-to-end cases. Every case still drives the real binary;
# these only remove the boilerplate around parsing a report and around
# signalling a live run.
module E2E
  extend self

  # v5's CSV columns in v5's order. v6 appends its new columns after these, so
  # this prefix is the compatibility guarantee header-indexed consumers rely on.
  V5_CSV_COLUMNS = [
    "url", "duration_mode", "requests", "responses", "transport_errors",
    "elapsed_seconds", "requests_per_second", "transfer_total_bytes",
    "transfer_size_per_request_bytes", "transfer_bytes_per_second",
    "latency_avg_ms", "latency_min_ms", "latency_stdev_ms", "latency_max_ms",
    "latency_p50_ms", "latency_p90_ms", "latency_p95_ms", "latency_p99_ms",
    "latency_p999_ms", "status_successful_count", "status_successful_percent",
    "status_failed_count", "status_failed_percent", "transport_error_percent",
    "status_successes", "status_code_distribution", "transport_error_distribution",
  ]

  V6_CSV_COLUMNS = [
    "schema_version", "cryload_version", "workers", "latency_correction",
    "latency_corrected_p50_ms", "latency_corrected_p90_ms",
    "latency_corrected_p95_ms", "latency_corrected_p99_ms",
    "latency_corrected_p999_ms", "send_delay_p50_ms", "send_delay_p99_ms",
    "rate_requested_per_second", "rate_attained_per_second",
    "rate_attainment_percent", "rate_skipped_requests",
    "rate_schedule_drift_ms", "phase_dns_p50_ms", "phase_connect_p50_ms",
    "phase_tls_p50_ms", "phase_ttfb_p50_ms", "thresholds_passed",
    "thresholds_breached", "exit_code",
  ]

  def json_run(args : Array(String)) : Tuple(Int32, JSON::Any)
    output = IO::Memory.new
    process = run_cryload(args, output: output)
    {process.exit_code, JSON.parse(output.to_s)}
  end

  def text_run(args : Array(String)) : Tuple(Int32, String, String)
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(args, output: output, error: error)
    {process.exit_code, output.to_s, error.to_s}
  end

  # For runs that used to hang: a regression must fail the spec instead of
  # stalling the suite until the CI job is killed.
  def bounded_json_run(args : Array(String), limit : Time::Span = 15.seconds) : Tuple(Int32, JSON::Any)
    output = IO::Memory.new
    process = Process.new(
      CRYLOAD_BIN, args,
      input: Process::Redirect::Close,
      output: output,
      error: Process::Redirect::Close,
      chdir: PROJECT_ROOT,
    )
    finished = Channel(Process::Status).new(1)
    spawn { finished.send process.wait }

    select
    when status = finished.receive
      {status.exit_code, JSON.parse(output.to_s)}
    when timeout(limit)
      process.terminate(graceful: false)
      fail "cryload did not finish within #{limit}: #{args.join(' ')}"
    end
  end

  def first_transport_error_category(report : JSON::Any) : String
    report["status"]["transport_errors"][0]["category"].as_s
  end

  # Lets a run gather `warmup` worth of samples, signals it, then collects the
  # report it prints on the way out.
  def signal_run(args : Array(String), signal : Signal, warmup : Time::Span = 1.second) : Tuple(Int32, String)
    reader, writer = IO.pipe
    process = Process.new(
      CRYLOAD_BIN, args,
      input: Process::Redirect::Close,
      output: writer,
      error: Process::Redirect::Close,
      chdir: PROJECT_ROOT,
    )
    writer.close
    sleep warmup
    process.signal signal
    report = reader.gets_to_end
    reader.close
    {process.wait.exit_code, report}
  end

  def with_urls_file(urls : Array(String), &)
    path = File.join(Dir.tempdir, "cryload-e2e-urls-#{Random.rand(1_000_000)}.txt")
    File.write(path, urls.join("\n") + "\n")
    begin
      yield path
    ensure
      File.delete? path
    end
  end
end

describe "Cryload E2E" do
  fixture_body_file = File.join(File.dirname(__DIR__), "spec", "support", "request-body.json")

  it "completes requests and prints final stats" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn do
      server.listen
    end

    sleep 100.milliseconds

    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "10"], output: output, error: error)

    server.close
    Fiber.yield

    process.exit_code.should eq(0)
    output.to_s.should contain("Preparing to make it CRY for 10 requests")
    output.to_s.should contain("Mode: request-count")
    output.to_s.should contain("Connections: 10")
    output.to_s.should contain("Workers:")
    output.to_s.should contain("Latency correction: on")
    output.to_s.should contain("Timeout: none")
    output.to_s.should contain("Request timeout: none")
    output.to_s.should contain("Total data:")
    output.to_s.should contain("Successful:")
    output.to_s.should contain("min:")
    output.to_s.should contain("Fastest:")
    output.to_s.should contain("Summary")
    output.to_s.should contain("Status")
    output.to_s.should contain("Latency Histogram (ms)")
    output.to_s.should contain("Latency Distribution (ms)")
    output.to_s.should contain("Latency Phases (ms)")
    # No gate configured, one URL, no rate: none of the optional blocks print.
    output.to_s.should_not contain("Thresholds")
    output.to_s.should_not contain("Per-URL")
    output.to_s.should_not contain("Corrected Latency Percentiles")
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
    run_cryload(["http://127.0.0.1:#{port}", "-n", "10"], output: output)

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
    run_cryload(["http://127.0.0.1:#{port}", "-n", "5"], output: output)

    server.close

    output.to_s.should contain("Failed: 5")
    output.to_s.should contain("Status Code Distribution")
    output.to_s.should contain("[404] 5 responses (100.0%)")
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
    run_cryload(["http://127.0.0.1:#{port}", "-n", "20", "-c", "5"], output: output)

    server.close

    output.to_s.should contain("Running load test @")
    output.to_s.should contain("Total requests: 20")
  end

  it "prints help when -h is passed" do
    output = IO::Memory.new
    process = run_cryload(["-h"], output: output)

    process.exit_code.should eq(0)
    output.to_s.should contain("HTTP load testing for CI/CD")
    output.to_s.should contain("honest latency")
    output.to_s.should contain("ab/wrk alternative")
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
    output.to_s.should contain("--version")
    output.to_s.should contain("--fail-on-error")
    output.to_s.should contain("--fail-on-transport-error")
    output.to_s.should contain("--max-fail-rate")
    output.to_s.should contain("--max-p99")
    output.to_s.should contain("--workers")
    output.to_s.should contain("--request-timeout")
    output.to_s.should contain("--latency-correction")
    output.to_s.should contain("--fail-on-rate-miss")
    output.to_s.should contain("--min-rps")
    output.to_s.should contain("--url-threshold")
  end

  it "prints version when -V is passed" do
    output = IO::Memory.new
    process = run_cryload(["-V"], output: output)

    process.exit_code.should eq(0)
    output.to_s.strip.should eq("cryload #{Cryload::VERSION}")
  end

  it "prints version when --version is passed" do
    output = IO::Memory.new
    process = run_cryload(["--version"], output: output)

    process.exit_code.should eq(0)
    output.to_s.strip.should start_with("cryload ")
  end

  it "exits with a config error when url is missing" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["-n", "10"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("cryload <url>")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when neither -n nor -d is specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("-n")
    combined.should contain("-d")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when both -n and -d are specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "-d", "5"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one mode")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when url is invalid" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["localhost:8080", "-n", "10"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid URL")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when the body file is missing" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--body-file", "/nonexistent/body.json"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Body file not found")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when the urls file is missing" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["--urls-file", "/nonexistent/urls.txt", "-n", "5"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("URLs file not found")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on non-positive connections" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "-c", "0"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Connections must be greater than 0")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on non-positive request counts and durations" do
    numbers_code, numbers_output, numbers_error = E2E.text_run(["http://localhost:8080", "-n", "0"])
    duration_code, duration_output, duration_error = E2E.text_run(["http://localhost:8080", "-d", "0"])

    numbers_code.should eq(2)
    (numbers_output + numbers_error).should contain("Number of requests must be greater than 0")
    duration_code.should eq(2)
    (duration_output + duration_error).should contain("Duration must be greater than 0")
  end

  it "exits 3 when the target is never reachable" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:19999", "-n", "5"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Connection failed")
    combined.should contain("Continuing and counting transport errors")
    output.to_s.should contain("Transport errors: 5 (100.0%)")
    output.to_s.should contain("Error Distribution")
    output.to_s.should contain("[connect_refused] 5 errors (100.0%)")
    process.exit_code.should eq(3)
  end

  it "reports a connect that exceeds --timeout as connect_timeout" do
    ConnectBlackhole.open do |port|
      code, report = E2E.bounded_json_run(["http://127.0.0.1:#{port}", "-n", "2", "-c", "1", "--timeout", "300ms", "--json"])

      code.should eq(3)
      E2E.first_transport_error_category(report).should eq("connect_timeout")
    end
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
    run_cryload(["http://127.0.0.1:#{port}", "-d", "1", "-c", "3"], output: output)

    server.close

    output.to_s.should contain("Preparing to make it CRY for 1s")
    output.to_s.should contain("Mode: duration (1s)")
    output.to_s.should contain("Total requests:")
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
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "-m", "POST", "-H", "X-Cryload-Test: ok", "-b", "hello"], output: output)

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
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "3", "-m", "POST", "--body-file", fixture_body_file, "--basic-auth", "user:secret", "-H", "Content-Type: application/json"], output: output)

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
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "3", "--user-agent", "cryload-test/1.0", "--host-header", "bench.local"], output: output)

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
    process = run_cryload(["http://127.0.0.1:#{port}/redirect", "-n", "3"], output: output)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 0")
    output.to_s.should contain("Failed: 3")
    output.to_s.should contain("Status Code Distribution")
    output.to_s.should contain("[302] 3 responses (100.0%)")
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
    process = run_cryload(["http://127.0.0.1:#{port}/redirect", "-n", "3", "--follow-redirects"], output: output)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
    output.to_s.should contain("Failed: 0")
    output.to_s.should contain("Status Code Distribution")
    output.to_s.should contain("[200] 3 responses (100.0%)")
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
    process = run_cryload(["http://127.0.0.1:#{port}/redirect", "-n", "3", "--success-status", "200-299,302"], output: output)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
    output.to_s.should contain("Failed: 0")
    output.to_s.should contain("Success statuses: 200-299, 302")
  end

  it "exits with a config error on invalid success status format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--success-status", "abc"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid success status")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on invalid header format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "-H", "InvalidHeader"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid header format")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when body and body-file are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--body", "inline", "--body-file", fixture_body_file], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one body source")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when body and body-stdin are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--body", "inline", "--body-stdin"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one body source")
    process.exit_code.should eq(2)
  end

  it "reads the request body from stdin with --body-stdin" do
    received_body = ""
    server, port = TestServer.start do |context|
      received_body = context.request.body.try(&.gets_to_end) || ""
      context.response.status_code = 200
      context.response.print "OK"
    end

    output = IO::Memory.new
    input = IO::Memory.new(%({"from":"stdin"}))
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "1", "-m", "POST", "--body-stdin"], output: output, input: input)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 1")
    received_body.should eq(%({"from":"stdin"}))
  end

  it "exits with a config error on invalid basic auth format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--basic-auth", "invalid"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid basic auth format")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when basic auth and authorization header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--basic-auth", "user:secret", "-H", "Authorization: Bearer token"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one authorization source")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when user-agent flag and User-Agent header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--user-agent", "cryload-test/1.0", "-H", "User-Agent: other"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one User-Agent source")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when host-header flag and Host header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--host-header", "bench.local", "-H", "Host: other.local"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one Host header source")
    process.exit_code.should eq(2)
  end

  it "sends 'Connection: close' on every request with --disable-keepalive" do
    server, port = TestServer.start do |context|
      if context.request.headers["Connection"]? == "close"
        context.response.status_code = 200
        context.response.print "closed"
      else
        context.response.status_code = 500
        context.response.print "keep-alive"
      end
    end

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--disable-keepalive"], output: output)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Keep-alive: disabled")
    output.to_s.should contain("Successful: 5")
  end

  it "exits with a config error when disable-keepalive and Connection header are both specified" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--disable-keepalive", "-H", "Connection: keep-alive"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one Connection source")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on invalid http method" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "-m", "FOO"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid HTTP method")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on non-positive timeout" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--timeout", "0"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Timeout must be greater than 0")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on non-positive rate" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--rate", "0"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Rate must be greater than 0 requests/sec")
    process.exit_code.should eq(2)
  end

  it "exits with a config error instead of crashing on non-finite or out-of-range numbers" do
    [
      {["--rate", "inf"], "Invalid value 'inf' for -q/--rate"},
      {["--rate", "nan"], "Invalid value 'nan' for -q/--rate"},
      {["--rate", "1e-10"], "Rate must be at least"},
      {["--max-p99", "nan"], "Invalid value 'nan' for --max-p99"},
      {["--min-rps", "inf"], "Invalid value 'inf' for --min-rps"},
      {["--max-fail-rate", "nan"], "Invalid value 'nan' for --max-fail-rate"},
      {["--url-threshold", "/ max-p99 inf"], "Invalid --url-threshold value 'inf'"},
      {["-d", "inf"], "Invalid duration 'inf' for -d"},
      {["--timeout", "1e10"], "Invalid duration '1e10' for --timeout"},
      {["--warmup", "99999999999h"], "Invalid duration '99999999999h' for --warmup"},
    ].each do |flag_args, message|
      code, output, error = E2E.text_run(["http://localhost:8080", "-n", "5"] + flag_args)

      combined = output + error
      combined.should_not contain("Unhandled exception")
      combined.should contain(message)
      code.should eq(2)
    end
  end

  it "renders a huge but finite threshold limit in the report" do
    server, port = TestServer.start do |context|
      context.response.print "OK"
    end

    code, output, error = E2E.text_run(["http://127.0.0.1:#{port}", "-n", "3", "--max-p99", "1e300", "--rate", "1e19"])

    server.close

    (output + error).should_not contain("Unhandled exception")
    output.should contain("1.0e+300")
    code.should eq(0)
  end

  it "exits with a config error on invalid output format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--output-format", "xml"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid output format")
    process.exit_code.should eq(2)
  end

  it "exits with a config error when --json conflicts with another output format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--json", "--output-format", "csv"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Please specify only one JSON output source")
    process.exit_code.should eq(2)
  end

  it "outputs json with --json including p95 and p99" do
    response_body = "OK"
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print response_body
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "20", "--json"], output: output)

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["summary"]["requests"].as_i.should eq(20)
    parsed["summary"]["responses"].as_i.should eq(20)
    parsed["summary"]["transport_errors"].as_i.should eq(0)
    parsed["summary"]["failure_rate_percent"].as_f.should eq(0.0)
    parsed["transfer"]["total_bytes"].as_i.should eq(response_body.bytesize * 20)
    parsed["transfer"]["size_per_request_bytes"].as_f.should eq(response_body.bytesize.to_f)
    parsed["transfer"]["bytes_per_second"].as_f.should be > 0.0
    parsed["latency_ms"]["min"].as_f.should be >= 0.0
    parsed["latency_ms"]["p10"].as_f.should be >= 0.0
    parsed["latency_ms"]["p50"].as_f.should be >= 0.0
    parsed["latency_ms"]["p95"].as_f.should be >= 0.0
    parsed["latency_ms"]["p99"].as_f.should be >= 0.0
    parsed["latency_ms"]["p999"].as_f.should be >= 0.0
    parsed["latency_histogram"].as_a.size.should be > 0
    parsed["latency_histogram"][0]["count"].as_i.should be >= 0
    parsed["status"]["successful_count"].as_i.should eq(20)
    parsed["status"]["successful_percent"].as_f.should eq(100.0)
    parsed["status"]["failed_count"].as_i.should eq(0)
    parsed["status"]["failed_percent"].as_f.should eq(0.0)
    parsed["status"]["transport_error_percent"].as_f.should eq(0.0)
    parsed["status"]["success_statuses"][0].as_s.should eq("200-299")
    parsed["status"]["codes"][0]["code"].as_s.should eq("200")
    parsed["status"]["codes"][0]["percent"].as_f.should eq(100.0)
  end

  it "stamps the json report with schema_version and cryload_version" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "3", "--json"])

    server.close

    code.should eq(0)
    parsed["schema_version"].as_i.should eq(1)
    parsed["cryload_version"].as_s.should_not be_empty
    parsed["cryload_version"].as_s.should eq(Cryload::VERSION)
  end

  it "outputs csv with --output-format csv" do
    response_body = "hello"
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print response_body
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--output-format", "csv"], output: output)

    server.close

    process.exit_code.should eq(0)
    lines = output.to_s.lines.map(&.strip).reject(&.empty?)
    lines.size.should eq(2)
    # v5 consumers index columns by position, so the v5 prefix must not move.
    lines[0].should contain("url,duration_mode,requests,responses,transport_errors,elapsed_seconds,requests_per_second,transfer_total_bytes,transfer_size_per_request_bytes,transfer_bytes_per_second,latency_avg_ms,latency_min_ms,latency_stdev_ms,latency_max_ms")
    lines[1].should contain(",25,5.0,")

    rows = CSV.parse(output.to_s)
    header = rows[0]
    header[0, E2E::V5_CSV_COLUMNS.size].should eq(E2E::V5_CSV_COLUMNS)
    header[E2E::V5_CSV_COLUMNS.size..].should eq(E2E::V6_CSV_COLUMNS)
    rows[1].size.should eq(header.size)

    row = Hash.zip(header, rows[1])
    row["schema_version"].should eq("1")
    row["cryload_version"].should eq(Cryload::VERSION)
    row["workers"].should_not be_empty
    row["latency_correction"].should eq("true")
    row["thresholds_passed"].should eq("true")
    row["exit_code"].should eq("0")
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
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--output-format", "quiet"], output: output)

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
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "6", "-c", "6", "--rate", "3", "--json"], output: output)

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["summary"]["requests"].as_i.should eq(6)
    parsed["summary"]["responses"].as_i.should eq(6)
    parsed["summary"]["elapsed_seconds"].as_f.should be >= 1.5
    parsed["summary"]["elapsed_seconds"].as_f.should be < 2.4
    parsed["summary"]["requests_per_second"].as_f.should be >= 2.5
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
    process = run_cryload(["http://127.0.0.1:#{port}", "-d", "2", "-c", "20", "--rate", "20", "--json"], output: output)

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["summary"]["elapsed_seconds"].as_f.should be < 2.2
    parsed["summary"]["requests"].as_i.should be >= 35
    parsed["summary"]["requests_per_second"].as_f.should be >= 17.0
  end

  it "stops duration mode at the configured deadline without waiting for late responses" do
    # Response must arrive well after the drain window (deadline + 500ms)
    # closes, otherwise this test races with the drain timer.
    server = HTTP::Server.new do |context|
      sleep 2500.milliseconds
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-d", "1", "-c", "5", "--json"], output: output)

    server.close

    process.exit_code.should eq(0)
    parsed = JSON.parse(output.to_s)
    parsed["summary"]["elapsed_seconds"].as_f.should be < 1.2
    parsed["summary"]["requests"].as_i.should eq(0)
    parsed["summary"]["responses"].as_i.should eq(0)
  end

  it "outputs normalized transport errors in json when target is unreachable" do
    code, parsed = E2E.json_run(["http://127.0.0.1:19999", "-n", "3", "--json"])

    code.should eq(3)
    parsed["summary"]["requests"].as_i.should eq(3)
    parsed["summary"]["responses"].as_i.should eq(0)
    parsed["summary"]["transport_errors"].as_i.should eq(3)
    parsed["status"]["transport_error_percent"].as_f.should eq(100.0)
    parsed["status"]["transport_errors"][0]["category"].as_s.should eq("connect_refused")
    parsed["status"]["transport_errors"][0]["percent"].as_f.should eq(100.0)
    parsed["status"]["transport_errors"][0]["sample_message"].as_s.should_not be_empty
    parsed["verdict"]["exit_code"].as_i.should eq(3)
    parsed["verdict"]["reason"].as_s.should eq("target_unreachable")
  end

  it "exits with error when --fail-on-error sees HTTP failures" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 404
      context.response.print "Not Found"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--fail-on-error", "--output-format", "quiet"], output: output)

    server.close

    process.exit_code.should eq(1)
  end

  it "passes when --fail-on-error sees only successful responses" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--fail-on-error", "--output-format", "quiet"], output: output)

    server.close

    process.exit_code.should eq(0)
  end

  it "exits with error when --max-fail-rate is exceeded" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 404
      context.response.print "Not Found"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    text_code, text_output, _ = E2E.text_run(["http://127.0.0.1:#{port}", "-n", "4", "--max-fail-rate", "25"])
    json_code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "4", "--max-fail-rate", "25", "--json"])

    server.close

    text_code.should eq(1)
    text_output.should contain("Thresholds")
    text_output.should contain("FAIL")
    text_output.should contain("fail_rate_percent")

    json_code.should eq(1)
    parsed["thresholds"]["passed"].as_bool.should be_false
    parsed["thresholds"]["evaluated"][0]["name"].as_s.should eq("max-fail-rate")
    parsed["thresholds"]["evaluated"][0]["metric"].as_s.should eq("fail_rate_percent")
    parsed["thresholds"]["evaluated"][0]["passed"].as_bool.should be_false
    breached = parsed["thresholds"]["breached"].as_a
    breached.size.should eq(1)
    breached[0]["name"].as_s.should eq("max-fail-rate")
    breached[0]["passed"].as_bool.should be_false
    parsed["verdict"]["exit_code"].as_i.should eq(1)
    parsed["verdict"]["reason"].as_s.should eq("threshold_breached")
  end

  it "exits with a config error on invalid max fail rate" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--max-fail-rate", "150"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Max fail rate must be between 0 and 100")
    process.exit_code.should eq(2)
  end

  it "sends cookies with --cookie" do
    cookie_value = Atomic(String?).new(nil)
    server = HTTP::Server.new do |context|
      cookie_value.set(context.request.headers["Cookie"]?)
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    run_cryload(["http://127.0.0.1:#{port}", "-n", "1", "--cookie", "session=abc123"], output: output)

    server.close

    cookie_value.get.should eq("session=abc123")
    output.to_s.should contain("Successful: 1")
  end

  it "loads targets from --urls-file without a positional URL" do
    count_a = Atomic(Int32).new(0)
    count_b = Atomic(Int32).new(0)

    server_a = HTTP::Server.new do |context|
      count_a.add(1)
      context.response.status_code = 200
      context.response.print "A"
    end
    server_b = HTTP::Server.new do |context|
      count_b.add(1)
      context.response.status_code = 200
      context.response.print "B"
    end

    address_a = server_a.bind_unused_port
    address_b = server_b.bind_unused_port

    urls_file = File.join(Dir.tempdir, "cryload-urls-#{Random.rand(100_000)}.txt")
    File.write(urls_file, "http://127.0.0.1:#{address_a.port}\nhttp://127.0.0.1:#{address_b.port}\n")

    spawn { server_a.listen }
    spawn { server_b.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    run_cryload(["--urls-file", urls_file, "-n", "10", "-c", "2"], output: output)

    server_a.close
    server_b.close

    count_a.get.should be > 0
    count_b.get.should be > 0
    output.to_s.should contain("(+1 more)")
    output.to_s.should contain("Successful: 10")
  ensure
    File.delete?(urls_file) if urls_file
  end

  it "excludes warmup traffic from timed stats" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--warmup", "1"], output: output)

    server.close

    output.to_s.should contain("Successful: 5")
  end

  it "appends random path segments with --random-path" do
    paths = [] of String
    paths_mutex = Mutex.new

    server = HTTP::Server.new do |context|
      paths_mutex.synchronize { paths << context.request.path }
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    run_cryload(["http://127.0.0.1:#{port}", "-n", "5", "--random-path"], output: output)

    server.close

    paths.size.should eq(5)
    paths.each(&.should_not(eq("/")))
    paths.uniq.size.should eq(5)
    output.to_s.should contain("Successful: 5")
  end

  it "shows warmup in the text header" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    run_cryload(["http://127.0.0.1:#{port}", "-n", "1", "--warmup", "1"], output: output)

    server.close

    output.to_s.should contain("Warmup: 1s")
    output.to_s.should contain("Warming up for 1s")
  end

  it "accepts self-signed HTTPS certificates with --insecure" do
    server, port = TestTls.start do |context|
      context.response.status_code = 200
      context.response.print "secure-ok"
    end

    output = IO::Memory.new
    process = run_cryload(["https://127.0.0.1:#{port}", "-n", "3", "--insecure", "--no-progress"], output: output)

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
  end

  it "exits with a config error on invalid proxy URL" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--proxy", "ftp://proxy.local:8080"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid proxy URL")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on invalid cookie format" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--cookie", "invalid-cookie"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid cookie format")
    process.exit_code.should eq(2)
  end

  it "exits with a config error on negative warmup" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://localhost:8080", "-n", "5", "--warmup", "-1"], output: output, error: error)

    combined = output.to_s + error.to_s
    combined.should contain("Invalid duration '-1' for --warmup")
    process.exit_code.should eq(2)
  end

  it "shows live progress on stderr with --progress" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    address = server.bind_unused_port
    port = address.port

    spawn { server.listen }
    sleep 100.milliseconds

    output = IO::Memory.new
    error = IO::Memory.new
    process = run_cryload(["http://127.0.0.1:#{port}", "-n", "20", "-c", "2", "--progress"], output: output, error: error)

    server.close

    process.exit_code.should eq(0)
    error.to_s.should contain("Progress:")
    error.to_s.should contain("req/s")
    output.to_s.should contain("Successful: 20")
  end

  it "keeps stderr clean when stderr is not a TTY and --progress is absent" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, output, error = E2E.text_run(["http://127.0.0.1:#{port}", "-n", "20", "-c", "2"])

    server.close

    code.should eq(0)
    output.should contain("Successful: 20")
    error.should_not contain("Progress:")
  end

  it "routes HTTP requests through --proxy" do
    server, proxy_port, request_lines, lines_mutex = MockProxy.start
    target_port = 19_999

    output = IO::Memory.new
    process = run_cryload(
      ["http://127.0.0.1:#{target_port}", "--proxy", "http://127.0.0.1:#{proxy_port}", "-n", "3", "--no-progress"],
      output: output,
    )

    server.close

    process.exit_code.should eq(0)
    output.to_s.should contain("Successful: 3")
    lines_mutex.synchronize do
      request_lines.any? { |line| line.includes?("http://127.0.0.1:#{target_port}") }.should be_true
    end
  end

  it "sends proxy credentials on plain-HTTP requests through --proxy" do
    server, proxy_port, request_lines, lines_mutex = MockProxy.start

    code, _, _ = E2E.text_run(["http://127.0.0.1:19999", "--proxy", "http://user:pass@127.0.0.1:#{proxy_port}", "-n", "2"])

    server.close

    code.should eq(0)
    lines_mutex.synchronize do
      request_lines.count("Proxy-Authorization: Basic #{Base64.strict_encode("user:pass")}").should eq(2)
    end
  end

  # v6: multi-core load generation -----------------------------------------

  it "reports the requested --workers count" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    single_code, single = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "12", "-c", "4", "--workers", "1", "--json"])
    multi_code, multi = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "12", "-c", "4", "--workers", "4", "--json"])

    server.close

    single_code.should eq(0)
    multi_code.should eq(0)
    single["config"]["workers"].as_i.should eq(1)
    multi["config"]["workers"].as_i.should eq(4)
    single["summary"]["responses"].as_i.should eq(12)
    multi["summary"]["responses"].as_i.should eq(12)
  end

  it "caps --workers at the connection count" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "8", "-c", "2", "--workers", "8", "--json"])

    server.close

    code.should eq(0)
    parsed["config"]["workers"].as_i.should eq(2)
    parsed["config"]["connections"].as_i.should eq(2)
  end

  it "exits with a config error on non-positive --workers" do
    code, output, error = E2E.text_run(["http://localhost:8080", "-n", "5", "--workers", "0"])

    (output + error).should contain("Workers must be greater than 0")
    code.should eq(2)
  end

  # v6: duration units ------------------------------------------------------

  it "accepts sub-second durations with -d" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    started = Time.instant
    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-d", "500ms", "-c", "2", "--json"])
    elapsed = Time.instant - started

    server.close

    code.should eq(0)
    elapsed.should be < 5.seconds
    parsed["duration_mode"].as_bool.should be_true
    parsed["summary"]["elapsed_seconds"].as_f.should be_close(0.5, 0.3)
  end

  it "treats -d 1s and -d 1 identically" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    unit_code, unit_output, _ = E2E.text_run(["http://127.0.0.1:#{port}", "-d", "1s", "-c", "2"])
    bare_code, bare_output, _ = E2E.text_run(["http://127.0.0.1:#{port}", "-d", "1", "-c", "2"])

    server.close

    unit_code.should eq(0)
    bare_code.should eq(0)
    unit_mode = unit_output.lines.find(&.starts_with?("Mode:"))
    bare_mode = bare_output.lines.find(&.starts_with?("Mode:"))
    unit_mode.should eq("Mode: duration (1s)")
    bare_mode.should eq(unit_mode)
  end

  it "exits with a config error on a malformed duration" do
    code, output, error = E2E.text_run(["http://localhost:8080", "-d", "5x"])

    (output + error).should contain("Invalid duration '5x'")
    code.should eq(2)
  end

  # v6: timeouts ------------------------------------------------------------

  it "categorizes an expired --timeout as read_timeout" do
    server, port = TestServer.start do |context|
      sleep 2.seconds
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "3", "-c", "3", "--timeout", "250ms", "--json"])

    server.close

    code.should eq(3)
    parsed["summary"]["responses"].as_i.should eq(0)
    parsed["summary"]["transport_errors"].as_i.should eq(3)
    errors = parsed["status"]["transport_errors"].as_a
    errors.size.should eq(1)
    errors[0]["category"].as_s.should eq("read_timeout")
    errors[0]["count"].as_i.should eq(3)
    errors[0]["sample_message"].as_s.should_not be_empty
    parsed["config"]["timeout_seconds"].as_f.should be_close(0.25, 0.001)
    parsed["verdict"]["reason"].as_s.should eq("target_unreachable")
  end

  it "stops a slow-trickle response with --request-timeout" do
    # The body arrives in small writes 100ms apart, so no single socket read
    # ever exceeds --timeout; only a total per-request deadline can stop it.
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.headers["Content-Type"] = "text/plain"
      20.times do
        context.response.print "x" * 64
        context.response.flush
        sleep 100.milliseconds
      end
    end

    deadlined_code, deadlined = E2E.json_run([
      "http://127.0.0.1:#{port}", "-n", "2", "-c", "2",
      "--timeout", "500ms", "--request-timeout", "1s", "--json",
    ])
    plain_code, plain = E2E.json_run([
      "http://127.0.0.1:#{port}", "-n", "1", "-c", "1", "--timeout", "500ms", "--json",
    ])

    server.close

    deadlined_code.should eq(3)
    deadlined["summary"]["responses"].as_i.should eq(0)
    deadlined["summary"]["transport_errors"].as_i.should eq(2)
    deadlined["status"]["transport_errors"].as_a.map(&.["category"].as_s).should eq(["request_timeout"])
    deadlined["config"]["request_timeout_seconds"].as_f.should eq(1.0)

    plain_code.should eq(0)
    plain["summary"]["responses"].as_i.should eq(1)
    plain["status"]["transport_errors"].as_a.should be_empty
    plain["config"]["request_timeout_seconds"].raw.should be_nil
  end

  it "exits with a config error when --request-timeout is shorter than --timeout" do
    code, output, error = E2E.text_run([
      "http://localhost:8080", "-n", "5", "--timeout", "5s", "--request-timeout", "500ms",
    ])

    combined = output + error
    combined.should contain("Request timeout")
    combined.should contain("must not be shorter than --timeout")
    code.should eq(2)
  end

  # v6: latency phases ------------------------------------------------------

  it "counts dns/connect phases per connection and ttfb/total per response" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "12", "-c", "3", "--json"])

    server.close

    code.should eq(0)
    responses = parsed["summary"]["responses"].as_i
    responses.should eq(12)
    phases = parsed["phases_ms"]
    phases["dns"]["count"].as_i.should eq(3)
    phases["connect"]["count"].as_i.should eq(3)
    # Plain HTTP performs no TLS handshake, so there is nothing to sample.
    phases["tls"]["count"].as_i.should eq(0)
    phases["ttfb"]["count"].as_i.should eq(responses)
    phases["total"]["count"].as_i.should eq(responses)
  end

  it "opens a connection per request with --disable-keepalive" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "9", "-c", "3", "--disable-keepalive", "--json"])

    server.close

    code.should eq(0)
    parsed["config"]["keepalive"].as_bool.should be_false
    parsed["phases_ms"]["connect"]["count"].as_i.should eq(parsed["summary"]["requests"].as_i)
  end

  # v6: per-status and per-url breakdowns -----------------------------------

  it "breaks latency down by status code" do
    counter = Atomic(Int32).new(0)
    server, port = TestServer.start do |context|
      context.response.status_code = counter.add(1).even? ? 200 : 503
      context.response.print "x"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "10", "-c", "1", "--json"])

    server.close

    code.should eq(0)
    entries = parsed["by_status"].as_a
    entries.size.should eq(2)
    entries.map(&.["code"].as_i).sort!.should eq([200, 503])
    entries.sum(&.["count"].as_i).should eq(parsed["summary"]["responses"].as_i)
    entries.each do |entry|
      entry["avg_ms"].as_f.should be > 0.0
      entry["p50_ms"].as_f.should be > 0.0
      entry["p99_ms"].as_f.should be >= entry["p50_ms"].as_f
    end
  end

  it "omits by_url for a single-URL run without a url threshold" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "5", "--json"])

    server.close

    code.should eq(0)
    parsed["by_url"].raw.should be_nil
  end

  it "reports one by_url entry per target for a --urls-file run" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    targets = ["http://127.0.0.1:#{port}/one", "http://127.0.0.1:#{port}/two"]

    E2E.with_urls_file(targets) do |path|
      code, parsed = E2E.json_run(["--urls-file", path, "-n", "8", "-c", "2", "--json"])

      code.should eq(0)
      entries = parsed["by_url"].as_a
      entries.size.should eq(2)
      entries.map(&.["url"].as_s).sort!.should eq(targets.sort)
      entries.sum(&.["requests"].as_i).should eq(parsed["summary"]["requests"].as_i)
      entries.sum(&.["responses"].as_i).should eq(parsed["summary"]["responses"].as_i)
      entries.each { |entry| entry["p99_ms"].as_f.should be >= entry["p50_ms"].as_f }
    end

    server.close
  end

  # v6: threshold matrix ----------------------------------------------------

  it "gates a single endpoint with --url-threshold" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}/api"
    pass_code, passed = E2E.json_run([url, "-n", "6", "--json", "--url-threshold", "/api max-p99 5000"])
    fail_code, failed = E2E.json_run([url, "-n", "6", "--json", "--url-threshold", "/api max-p99 0.001"])
    text_code, text_output, _ = E2E.text_run([url, "-n", "6", "--url-threshold", "/api max-p99 0.001"])

    server.close

    pass_code.should eq(0)
    passed["thresholds"]["passed"].as_bool.should be_true
    passed["thresholds"]["breached"].as_a.should be_empty
    passed["thresholds"]["evaluated"][0]["scope"].as_s.should eq("/api")
    passed["thresholds"]["evaluated"][0]["name"].as_s.should eq("max-p99")
    passed["by_url"].as_a.size.should eq(1)

    fail_code.should eq(1)
    failed["thresholds"]["passed"].as_bool.should be_false
    failed["thresholds"]["breached"].as_a.size.should eq(1)
    failed["thresholds"]["breached"][0]["scope"].as_s.should eq("/api")
    failed["verdict"]["reason"].as_s.should eq("threshold_breached")

    text_code.should eq(1)
    text_output.should contain("Thresholds")
    text_output.should contain("FAIL")
    text_output.should contain("Per-URL")
  end

  it "exits with a config error when a --url-threshold pattern matches no target" do
    code, output, error = E2E.text_run([
      "http://localhost:8080", "-n", "5", "--url-threshold", "/missing max-p99 100",
    ])

    (output + error).should contain("matches none of the 1 target URL(s)")
    code.should eq(2)
  end

  it "scopes a --url-threshold to the slow endpoint of a two-URL run" do
    server, port = TestServer.start do |context|
      sleep 200.milliseconds if context.request.path.starts_with?("/slow")
      context.response.status_code = 200
      context.response.print "OK"
    end

    targets = ["http://127.0.0.1:#{port}/slow", "http://127.0.0.1:#{port}/fast"]

    E2E.with_urls_file(targets) do |path|
      slow_code, slow = E2E.json_run(["--urls-file", path, "-n", "8", "-c", "2", "--json", "--url-threshold", "/slow max-p99 25"])
      fast_code, fast = E2E.json_run(["--urls-file", path, "-n", "8", "-c", "2", "--json", "--url-threshold", "/fast max-p99 25"])

      slow_code.should eq(1)
      slow["thresholds"]["evaluated"][0]["scope"].as_s.should eq("/slow")
      slow["thresholds"]["evaluated"][0]["passed"].as_bool.should be_false
      slow["thresholds"]["evaluated"][0]["actual"].as_f.should be > 25.0
      slow["thresholds"]["breached"].as_a.size.should eq(1)
      slow["verdict"]["reason"].as_s.should eq("threshold_breached")

      fast_code.should eq(0)
      fast["thresholds"]["evaluated"][0]["scope"].as_s.should eq("/fast")
      fast["thresholds"]["evaluated"][0]["passed"].as_bool.should be_true
      fast["thresholds"]["evaluated"][0]["actual"].as_f.should be < 25.0
      fast["verdict"]["reason"].as_s.should eq("ok")
    end

    server.close
  end

  it "gates throughput with --min-rps" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}"
    high_code, high = E2E.json_run([url, "-n", "10", "--json", "--min-rps", "1000000"])
    low_code, low = E2E.json_run([url, "-n", "10", "--json", "--min-rps", "1"])

    server.close

    high_code.should eq(1)
    evaluated = high["thresholds"]["evaluated"][0]
    evaluated["name"].as_s.should eq("min-rps")
    evaluated["metric"].as_s.should eq("requests_per_second")
    evaluated["comparator"].as_s.should eq(">=")
    evaluated["passed"].as_bool.should be_false
    high["thresholds"]["passed"].as_bool.should be_false
    high["thresholds"]["breached"].as_a.size.should eq(1)
    high["thresholds"]["breached"][0]["name"].as_s.should eq("min-rps")
    high["verdict"]["reason"].as_s.should eq("threshold_breached")

    low_code.should eq(0)
    low["thresholds"]["passed"].as_bool.should be_true
    low["thresholds"]["breached"].as_a.should be_empty
    low["verdict"]["reason"].as_s.should eq("ok")
  end

  it "gates every --max-* latency metric" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}"
    {
      "--max-p50"     => "corrected_p50",
      "--max-p75"     => "corrected_p75",
      "--max-p90"     => "corrected_p90",
      "--max-p95"     => "corrected_p95",
      "--max-p99"     => "corrected_p99",
      "--max-p999"    => "corrected_p999",
      "--max-avg"     => "corrected_avg",
      "--max-latency" => "corrected_max",
    }.each do |flag, metric|
      breach_code, breached = E2E.json_run([url, "-n", "6", "--json", flag, "0.0001"])
      breach_code.should eq(1)
      evaluated = breached["thresholds"]["evaluated"].as_a
      evaluated.size.should eq(1)
      evaluated[0]["name"].as_s.should eq(flag.lchop("--"))
      evaluated[0]["metric"].as_s.should eq(metric)
      evaluated[0]["scope"].as_s.should eq("global")
      evaluated[0]["comparator"].as_s.should eq("<=")
      evaluated[0]["passed"].as_bool.should be_false
      breached["thresholds"]["passed"].as_bool.should be_false
      breached["thresholds"]["breached"].as_a.size.should eq(1)
      breached["thresholds"]["breached"][0]["name"].as_s.should eq(flag.lchop("--"))
      breached["verdict"]["reason"].as_s.should eq("threshold_breached")

      ok_code, ok = E2E.json_run([url, "-n", "6", "--json", flag, "10000"])
      ok_code.should eq(0)
      ok["thresholds"]["evaluated"][0]["name"].as_s.should eq(flag.lchop("--"))
      ok["thresholds"]["passed"].as_bool.should be_true
      ok["thresholds"]["breached"].as_a.should be_empty
      ok["verdict"]["reason"].as_s.should eq("ok")
    end

    server.close
  end

  it "shows a PASS/FAIL line per configured threshold in the text report" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, output, _ = E2E.text_run([
      "http://127.0.0.1:#{port}", "-n", "6", "--max-p99", "0.0001", "--min-rps", "1",
    ])

    server.close

    code.should eq(1)
    output.should contain("Thresholds")
    output.should contain("FAIL")
    output.should contain("PASS")
    output.should contain("corrected_p99")
    output.should contain("requests_per_second")
  end

  # v6: coordinated-omission correction ------------------------------------

  it "attains a serviceable --rate with --fail-on-rate-miss" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run([
      "http://127.0.0.1:#{port}", "-d", "1", "-c", "4", "-q", "50", "--fail-on-rate-miss", "--json",
    ])

    server.close

    code.should eq(0)
    parsed["config"]["rate_limit"].as_f.should eq(50.0)
    parsed["rate"]["requested_per_second"].as_f.should eq(50.0)
    parsed["rate"]["attainment_percent"].as_f.should be_close(100.0, 3.0)
    parsed["rate"]["scheduled_requests"].as_i.should eq(50)
    parsed["rate"]["skipped_requests"].as_i.should eq(0)
    parsed["verdict"]["reason"].as_s.should eq("ok")
  end

  it "exits with a config error for --fail-on-rate-miss without a rate" do
    code, output, error = E2E.text_run(["http://localhost:8080", "-n", "5", "--fail-on-rate-miss"])

    (output + error).should contain("needs a requested rate")
    code.should eq(2)
  end

  it "fills the rate block only when -q is set" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}"
    unlimited_code, unlimited = E2E.json_run([url, "-d", "500ms", "-c", "2", "--json"])
    limited_code, limited = E2E.json_run([url, "-d", "1", "-c", "2", "-q", "40", "--json"])

    server.close

    unlimited_code.should eq(0)
    unlimited["rate"]["requested_per_second"].raw.should be_nil
    unlimited["rate"]["attainment_percent"].raw.should be_nil
    unlimited["rate"]["scheduled_requests"].raw.should be_nil
    unlimited["rate"]["skipped_requests"].raw.should be_nil
    unlimited["rate"]["schedule_drift_ms"].raw.should be_nil
    unlimited["rate"]["attained_per_second"].as_f.should eq(unlimited["summary"]["requests_per_second"].as_f)

    limited_code.should eq(0)
    limited["rate"]["requested_per_second"].as_f.should eq(40.0)
    limited["rate"]["attained_per_second"].as_f.should be > 0.0
    limited["rate"]["attainment_percent"].as_f.should be > 0.0
    limited["rate"]["scheduled_requests"].as_i.should eq(40)
    limited["rate"]["skipped_requests"].as_i.should be >= 0
    limited["rate"]["schedule_drift_ms"].as_f.should be >= 0.0
  end

  it "mirrors latency into corrected_latency without -q" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, parsed = E2E.json_run(["http://127.0.0.1:#{port}", "-n", "20", "--json"])

    server.close

    code.should eq(0)
    latency = parsed["latency_ms"].as_h
    corrected = parsed["corrected_latency_ms"].as_h
    corrected.keys.sort!.should eq(latency.keys.sort!)
    latency.each do |key, value|
      corrected[key].as_f.should eq(value.as_f)
    end
    parsed["send_delay_ms"]["max"].as_f.should eq(0.0)
  end

  it "gates uncorrected latency with --latency-correction off" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}"
    on_code, on = E2E.json_run([url, "-n", "10", "--json", "--max-p99", "5000"])
    off_code, off = E2E.json_run([url, "-n", "10", "--json", "--max-p99", "5000", "--latency-correction", "off"])

    server.close

    on_code.should eq(0)
    off_code.should eq(0)
    on["config"]["latency_correction"].as_bool.should be_true
    on["thresholds"]["evaluated"][0]["metric"].as_s.should eq("corrected_p99")
    off["config"]["latency_correction"].as_bool.should be_false
    off["thresholds"]["evaluated"][0]["metric"].as_s.should eq("p99")
  end

  # v6: verdict and signals -------------------------------------------------

  it "matches verdict.exit_code to the process exit code" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    url = "http://127.0.0.1:#{port}"
    ok_code, ok = E2E.json_run([url, "-n", "5", "--json"])
    breach_code, breach = E2E.json_run([url, "-n", "5", "--json", "--max-p99", "0.0001"])

    server.close

    unreachable_code, unreachable = E2E.json_run(["http://127.0.0.1:19999", "-n", "3", "--json"])

    ok_code.should eq(0)
    ok["verdict"]["exit_code"].as_i.should eq(ok_code)
    ok["verdict"]["reason"].as_s.should eq("ok")

    breach_code.should eq(1)
    breach["verdict"]["exit_code"].as_i.should eq(breach_code)
    breach["verdict"]["reason"].as_s.should eq("threshold_breached")

    unreachable_code.should eq(3)
    unreachable["verdict"]["exit_code"].as_i.should eq(unreachable_code)
    unreachable["verdict"]["reason"].as_s.should eq("target_unreachable")
  end

  it "prints the report and exits 130 on SIGINT" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    # Workers flush their stats batch once per second, so the run needs more
    # than that before the signal for the report to carry any samples.
    code, report = E2E.signal_run(
      ["http://127.0.0.1:#{port}", "-d", "60", "-c", "2", "-q", "500", "--json"],
      Signal::INT,
      warmup: 1500.milliseconds,
    )

    server.close

    code.should eq(130)
    parsed = JSON.parse(report)
    parsed["summary"]["responses"].as_i.should be > 0
    parsed["verdict"]["exit_code"].as_i.should eq(130)
    parsed["verdict"]["reason"].as_s.should eq("interrupted")
  end

  it "prints the report and exits 143 on SIGTERM" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, report = E2E.signal_run(
      ["http://127.0.0.1:#{port}", "-d", "60", "-c", "2", "-q", "500", "--json"],
      Signal::TERM,
      warmup: 1500.milliseconds,
    )

    server.close

    code.should eq(143)
    parsed = JSON.parse(report)
    parsed["summary"]["responses"].as_i.should be > 0
    parsed["verdict"]["exit_code"].as_i.should eq(143)
    parsed["verdict"]["reason"].as_s.should eq("terminated")
  end

  it "lets a breached threshold outrank the signal exit code" do
    server, port = TestServer.start do |context|
      context.response.status_code = 200
      context.response.print "OK"
    end

    code, report = E2E.signal_run(
      ["http://127.0.0.1:#{port}", "-d", "60", "-c", "2", "-q", "500", "--max-p99", "0.0001", "--json"],
      Signal::INT,
      warmup: 1500.milliseconds,
    )

    server.close

    code.should eq(1)
    parsed = JSON.parse(report)
    parsed["verdict"]["exit_code"].as_i.should eq(1)
    parsed["verdict"]["reason"].as_s.should eq("threshold_breached")
    parsed["thresholds"]["passed"].as_bool.should be_false
    parsed["thresholds"]["breached"].as_a.size.should eq(1)
  end
end
