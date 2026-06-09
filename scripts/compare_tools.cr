require "json"
require "http/server"
require "option_parser"

ROOT = File.expand_path("..", __DIR__)

struct BenchmarkResult
  getter tool : String
  getter requests : Int64
  getter rps : Float64
  getter p50_ms : Float64
  getter p99_ms : Float64

  def initialize(@tool : String, @requests : Int64, @rps : Float64, @p50_ms : Float64, @p99_ms : Float64)
  end

  def to_s(io : IO) : Nil
    io << "reqs=#{@requests} rps=#{@rps.round.to_i} p50=#{@p50_ms.round(2)}ms p99=#{@p99_ms.round(2)}ms"
  end
end

module BenchServer
  def self.start : Int32
    server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.content_type = "text/plain"
      context.response.print "OK"
    end

    address = server.bind_tcp "127.0.0.1", 0
    spawn { server.listen }
    sleep 200.milliseconds
    address.port
  end
end

module OutputParser
  def self.cryload_json(output : String) : BenchmarkResult
    doc = JSON.parse(output)
    summary = doc["summary"]
    latency = doc["latency_ms"]

    BenchmarkResult.new(
      tool: "cryload",
      requests: summary["requests"].as_i64,
      rps: summary["requests_per_second"].as_f,
      p50_ms: latency["p50"].as_f,
      p99_ms: latency["p99"].as_f,
    )
  end

  def self.hey(output : String) : BenchmarkResult
    rps = 0.0
    requests = 0_i64
    p50_ms = 0.0
    p99_ms = 0.0

    output.each_line do |line|
      if line.includes?("Requests/sec:")
        rps = line.split(":", remove_empty: true)[1].strip.to_f
      end

      if match = line.match(/\[200\]\s+(\d+)\s+responses/)
        requests = match[1].to_i64
      end

      stripped = line.strip
      if stripped.starts_with?("50%")
        p50_ms = stripped.split[-2].to_f * 1000
      elsif stripped.starts_with?("99%")
        p99_ms = stripped.split[-2].to_f * 1000
      end
    end

    BenchmarkResult.new(tool: "hey", requests: requests, rps: rps, p50_ms: p50_ms, p99_ms: p99_ms)
  end

  def self.wrk(output : String) : BenchmarkResult
    requests = 0_i64
    rps = 0.0
    p50_ms = 0.0
    p99_ms = 0.0

    output.each_line do |line|
      if match = line.match(/(\d+)\s+requests in/)
        requests = match[1].to_i64
      end

      if line.includes?("Requests/sec:")
        rps = line.split(":", remove_empty: true)[1].strip.to_f
      end

      if match = line.match(/\b50%\s+([\d.]+)(us|ms)\b/)
        p50_ms = latency_to_ms(match[1].to_f, match[2])
      elsif match = line.match(/\b99%\s+([\d.]+)(us|ms)\b/)
        p99_ms = latency_to_ms(match[1].to_f, match[2])
      end
    end

    BenchmarkResult.new(tool: "wrk", requests: requests, rps: rps, p50_ms: p50_ms, p99_ms: p99_ms)
  end

  private def self.latency_to_ms(value : Float64, unit : String) : Float64
    unit == "ms" ? value : value / 1000
  end
end

class ToolRunner
  @cryload : String
  @hey : String
  @wrk : String

  def initialize(
    cryload : String = ENV["CRYLOAD"]? || File.join(ROOT, "bin", "cryload"),
    hey : String = ENV["HEY"]? || "hey",
    wrk : String = ENV["WRK"]? || "wrk",
  )
    @cryload = cryload
    @hey = hey
    @wrk = wrk
  end

  def cryload_path
    @cryload
  end

  def run_capture(command : Array(String)) : String
    output = IO::Memory.new
    program = command[0]
    args = command[1..]? || [] of String
    status = Process.run(program, args, output: output, error: Process::Redirect::Close)
    unless status.success?
      raise "command failed (#{status.exit_code}): #{command.join(" ")}"
    end
    output.to_s
  end

  def cryload_duration(url : String, duration : Int32, connections : Int32) : BenchmarkResult
    output = run_capture([
      @cryload, url,
      "-d", duration.to_s,
      "-c", connections.to_s,
      "--no-progress", "--json",
    ])
    OutputParser.cryload_json(output)
  end

  def cryload_requests(url : String, requests : Int32, connections : Int32) : BenchmarkResult
    output = run_capture([
      @cryload, url,
      "-n", requests.to_s,
      "-c", connections.to_s,
      "--no-progress", "--json",
    ])
    OutputParser.cryload_json(output)
  end

  def hey_duration(url : String, duration : Int32, connections : Int32) : BenchmarkResult
    output = run_capture([@hey, "-z", "#{duration}s", "-c", connections.to_s, url])
    OutputParser.hey(output)
  end

  def hey_requests(url : String, requests : Int32, connections : Int32) : BenchmarkResult
    output = run_capture([@hey, "-n", requests.to_s, "-c", connections.to_s, url])
    OutputParser.hey(output)
  end

  def wrk_duration(url : String, duration : Int32, connections : Int32) : BenchmarkResult
    output = run_capture([
      @wrk,
      "-t", connections.to_s,
      "-c", connections.to_s,
      "-d", "#{duration}s",
      "--latency",
      url,
    ])
    OutputParser.wrk(output)
  end
end

class CompareTools
  def initialize(
    @duration : Int32 = ENV["DURATION"]?.try(&.to_i) || 10,
    @connections : Int32 = ENV["CONNECTIONS"]?.try(&.to_i) || 50,
    @runner : ToolRunner = ToolRunner.new,
  )
  end

  def run
    unless File.exists?(@runner.cryload_path)
      STDERR.puts "cryload binary not found: #{@runner.cryload_path}"
      exit 1
    end

    port = BenchServer.start
    url = "http://127.0.0.1:#{port}"

    puts "Benchmark target: #{url} (Crystal HTTP::Server, 2-byte body)"
    puts "Duration: #{@duration}s  Connections: #{@connections}"
    puts

    run_duration_case(url, "duration mode (#{@duration}s, c=#{@connections})", @connections)
    run_duration_case(url, "duration mode (#{@duration}s, c=10)", 10)
    run_duration_case(url, "duration mode (#{@duration}s, c=100)", 100)

    requests = @duration * 15_000
    puts "=== request-count mode (-n #{requests}, c=50) ==="
    print_result @runner.cryload_requests(url, requests, 50)
    print_result @runner.hey_requests(url, requests, 50)
    puts "  wrk:     n/a (wrk has no native request-count mode)"
    puts
  end

  private def run_duration_case(url : String, label : String, connections : Int32)
    puts "=== #{label} ==="
    print_result @runner.cryload_duration(url, @duration, connections)
    print_result @runner.hey_duration(url, @duration, connections)
    print_result @runner.wrk_duration(url, @duration, connections)
    puts
  rescue ex
    STDERR.puts "  failed: #{ex.message}"
    puts
  end

  private def print_result(result : BenchmarkResult)
    printf("  %-8s %s\n", "#{result.tool}:", result)
  end
end

duration = ENV["DURATION"]?.try(&.to_i) || 10
connections = ENV["CONNECTIONS"]?.try(&.to_i) || 50

OptionParser.parse do |opts|
  opts.banner = "Usage: compare_tools [options]\n\nCompare cryload, hey, and wrk against a local bench server."

  opts.on("-d SECONDS", "--duration SECONDS", "Benchmark duration in seconds") do |value|
    duration = value.to_i
  end

  opts.on("-c CONNECTIONS", "--connections CONNECTIONS", "Default connection count") do |value|
    connections = value.to_i
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

CompareTools.new(duration: duration, connections: connections).run
