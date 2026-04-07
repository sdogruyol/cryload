# cryload - Powerful HTTP Benchmarking Tool

<p align="center">
  <img src="assets/logo.png" alt="cryload logo" width="240">
</p>

[![CI](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml/badge.svg)](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml)

cryload is a powerful, fast, and practical HTTP benchmarking tool for stress testing APIs and web services.

Built with [Crystal](https://crystal-lang.org/) for high performance and low overhead.

## Why cryload?

- High-throughput HTTP load testing with a lightweight CLI experience
- Concurrent benchmarking with configurable connection count
- Request count mode (`-n`) and duration mode (`-d`) support
- Flexible request customization (method, headers, body, body-file, auth, user-agent, host header, timeout, TLS)
- JSON output mode for CI/CD and automation workflows
- Richer latency percentiles plus response/error breakdowns
- Optional global request rate limiting with `--rate`

## Installation

### Option 1: Prebuilt binary (recommended)

Download the latest prebuilt binary from the [Releases page](https://github.com/sdogruyol/cryload/releases), then make it executable:

```bash
chmod +x cryload
./cryload --help
```

### Option 2: Build from source

Requires Crystal `1.19.0` or later.

```bash
git clone https://github.com/sdogruyol/cryload.git && cd cryload
shards build --release
```

The binary will be at `bin/cryload`.

## Quick Start

Run your first benchmark in seconds:

```bash
bin/cryload http://localhost:3000 -n 10000 -c 100
```

## Usage

```bash
cryload <url> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-n`, `--numbers` | Number of requests to make |
| `-d`, `--duration` | Duration of test in seconds |
| `-c`, `--connections` | Concurrent connections (default: 10) |
| `-m`, `--method` | HTTP method (default: GET) |
| `-b`, `--body` | HTTP request body |
| `--body-file` | Read HTTP request body from file |
| `-H`, `--header` | HTTP header, repeatable (`-H "Key: Value"`) |
| `--user-agent` | Set the `User-Agent` header |
| `--host-header` | Override the `Host` header |
| `-a`, `--basic-auth` | HTTP Basic auth in the form `user:password` |
| `--timeout` | Client connect/read timeout in seconds |
| `-q`, `--rate` | Total request rate limit in requests/sec |
| `-L`, `--follow-redirects` | Follow HTTP redirects up to 5 hops |
| `--output-format` | Output format: `text`, `json`, `csv`, `quiet` |
| `--success-status` | Treat specific status codes/ranges as successful |
| `--insecure` | Accept invalid TLS certificates for HTTPS |
| `--json` | Print final result as JSON |
| `-h`, `--help` | Show help |

**Examples:**

10,000 requests to localhost
```bash
cryload http://localhost:9292 -n 10000
```

10 seconds with 100 connections
```bash
cryload http://localhost:3000 -d 10 -c 100
```

Simple POST request
```bash
cryload http://localhost:3000/api/login -n 1000 -m POST
```

POST with plain text body
```bash
cryload http://localhost:3000/api/echo -n 500 -m POST -H "Content-Type: text/plain" -b "hello"
```

POST with JSON body
```bash
cryload http://localhost:3000/api -n 500 -m POST -H "Content-Type: application/json" -b '{"name":"cry"}' --timeout 5
```

POST JSON body from file
```bash
cryload http://localhost:3000/api -n 500 -m POST -H "Content-Type: application/json" --body-file payload.json
```

POST with multiple headers
```bash
cryload http://localhost:3000/api -n 300 -m POST -H "Authorization: Bearer token123" -H "X-Request-ID: benchmark-1" -b '{"ok":true}'
```

Basic auth request
```bash
cryload http://localhost:3000/private -n 300 --basic-auth username:password
```

Custom User-Agent and Host header
```bash
cryload http://127.0.0.1:3000 -n 300 --user-agent cryload-test/1.0 --host-header api.internal
```

Duration mode + timeout
```bash
cryload http://localhost:3000/api -d 15 -c 50 --timeout 3
```

Rate-limited run at 100 requests/sec total
```bash
cryload http://localhost:3000/api -n 1000 -c 50 --rate 100
```

Follow redirects
```bash
cryload http://localhost:3000/redirect -n 100 -L
```

Treat redirects as success without following them
```bash
cryload http://localhost:3000/redirect -n 100 --success-status 200-299,302
```

HTTPS with self-signed cert (skip TLS verification)
```bash
cryload https://localhost:8443 -n 1000 --insecure
```

JSON output for automation/CI
```bash
cryload http://localhost:3000/api -n 1000 --json
```

CSV output for scripts
```bash
cryload http://localhost:3000/api -n 1000 --output-format csv
```

Quiet mode for exit-code-only checks
```bash
cryload http://localhost:3000/health -n 10 --output-format quiet
```

**Example output:**

```
Preparing to make it CRY for 10 seconds with 100 connections!
Running load test @ http://localhost:3000/

  Latency (ms)      avg: 0.53   min: 0.19   stdev: 0.76   max: 35.39

  Percentiles (ms)  p50: 0.41   p90: 0.81   p95: 0.96
                    p99: 1.34   p999: 3.72

1696170 requests in 10.11s
Requests/sec:  167803.62
Responses: 1696170    Errors: 0 (0.0%)
Successful: 1696170 (100.0%)    Failed: 0 (0.0%)
Success statuses: 200-299
Status codes: 200: 1696170
```

## Built With Crystal

cryload is written in [Crystal](https://crystal-lang.org/), combining Ruby-like developer ergonomics with compiled-language speed.

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Open a Pull Request

## License

MIT
