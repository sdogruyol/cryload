<p align="left">
  <img src="assets/logo.png" alt="cryload logo" width="180">
</p>

# cryload

Cross-platform HTTP load testing CLI: a modern ab/wrk alternative with machine-readable reports for CI/CD

[![CI](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml/badge.svg)](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml)

**cryload** is a fast, single-binary **HTTP load testing** and **benchmarking CLI**: drive **concurrent** traffic against REST **APIs**, **microservices**, and static sites, measure **requests per second**, **latency percentiles** (p50–p999), status breakdowns, and transfer volume. Use it for **stress tests**, **smoke tests** before deploy, capacity checks, and **GitHub Actions** / pipeline automation via **JSON** or **CSV** output.

If you are looking for a **hey**-like or **oha**-like tool with extra reporting modes, or an **ab** / **wrk** alternative for **HTTP** scenarios without Lua scripting, cryload is built for that workflow. Implemented in **[Crystal](https://crystal-lang.org/)** for a small footprint and predictable performance.

Typical uses: bench **Node**, **Go**, **Python**, **Rails**, or **.NET** HTTP services; soak an **API gateway** or **Kubernetes** ingress; compare **p99 latency** after tuning; ship the same **macOS**, **Linux**, and **Windows** CLI to your team.

## How cryload compares to ab, wrk, hey, and oha

Rough feature snapshot (tools evolve; check each project’s docs for the latest).

| | cryload | [ab](https://httpd.apache.org/docs/current/programs/ab.html) | [hey](https://github.com/rakyll/hey) | [oha](https://github.com/hatoo/oha) | [wrk](https://github.com/wg/wrk) |
|--|:--:|:--:|:--:|:--:|:--:|
| Language | Crystal | C | Go | Rust | C |
| **Concurrent** connections (`-c`) | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Duration** / **request count** (`-n`) | ✓ | ✓ (`-t` / `-n`) | ✓ | ✓ | ✓ |
| **JSON** / **CSV** / quiet output for **CI/CD** | ✓ | — (text) | JSON | JSON | — (text / Lua) |
| Text latency **histogram** + distribution | ✓ | basic | limited | TUI-focused | basic |
| Global **RPS cap** (`--rate`) | ✓ | — | — | ✓ | different model |
| **Follow redirects**, custom **success** HTTP codes | ✓ | — | partial | partial | — |
| **Scriptable** load (Lua, etc.) | — | — | — | — | ✓ |

Choose **wrk** when you need Lua-driven scenarios and maximum tuning on Linux. Choose **ab** when the classic Apache **Bench** one-liner is enough—plain-text summaries, **GET**-heavy checks, and **httpd**-family packages already on the machine. Choose **hey** or **oha** when their defaults match your stack. Choose **cryload** when you want **CSV** / **JSON** reporting, **rate** limits, redirect handling, and **histogram**-style summaries in one **cross-platform** binary.

## Why cryload?

- High-throughput HTTP load testing with a lightweight CLI experience
- Concurrent benchmarking with configurable connection count
- Request count mode (`-n`) and duration mode (`-d`) support
- Flexible request customization (method, headers, body, body-file, auth, user-agent, host header, timeout, TLS)
- JSON output mode for CI/CD and automation workflows
- Richer latency percentiles plus response/error breakdowns
- Optional global request rate limiting with `--rate`

## Installation

### Option 1: Install script (recommended)

Downloads the matching asset from [Releases](https://github.com/sdogruyol/cryload/releases), verifies SHA256, and installs to `~/.local/bin` (or `%USERPROFILE%\.local\bin` on Windows).

**Linux / macOS** (needs `curl` or `wget`, and `sha256sum` or `shasum`):

```bash
curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

Install a specific version:

```bash
VERSION=v3.1.0 curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

**Windows** (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.ps1 | iex
```

### Option 2: Prebuilt binary

Download the latest prebuilt binary from the [Releases page](https://github.com/sdogruyol/cryload/releases), then make it executable:

```bash
chmod +x cryload
./cryload --help
```

### Option 3: Build from source

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
Mode: duration (10s)
Connections: 100
Rate limit: unlimited
Success statuses: 200-299

Summary
  Total requests: 1696170
  Total time: 10.11s
  Requests/sec: 167803.62
  Responses: 1696170
  Transport errors: 0 (0.0%)
  Fastest: 0.19 ms
  Slowest: 35.39 ms

Status
  Successful: 1696170 (100.0%)
  Failed: 0 (0.0%)
  Success statuses: 200-299

Transfer
  Total data: 374.14 MiB
  Size/request: 231.0 B
  Transfer/sec: 37.01 MiB/s

Latency (ms)
  avg: 0.53   min: 0.19   stdev: 0.76   max: 35.39

Latency Percentiles (ms)
  p50: 0.41   p90: 0.81   p95: 0.96
  p99: 1.34   p999: 3.72

Latency Histogram (ms)
  3.390 ms [120] |■■
  6.590 ms [420] |■■■■■■■
  9.790 ms [1690630] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

Latency Distribution (ms)
  10.0% in 0.32
  25.0% in 0.38
  50.0% in 0.41
  75.0% in 0.55
  90.0% in 0.81
  95.0% in 0.96
  99.0% in 1.34
  99.9% in 3.72

Status Code Distribution
  [200] 1696170 responses (100.0%)
```

## Built With Crystal

cryload is written in [Crystal](https://crystal-lang.org/), combining Ruby-like developer ergonomics with compiled-language speed.

## Automation and CI

Use **`--json`** or **`--output-format csv`** for scripts, dashboards, and **GitHub Actions** jobs: parse a single structured summary instead of scraping text. **`--output-format quiet`** is useful when you only care about exit status after a small **health-check** load. Combine with **`-n`** for fixed request counts so pipelines stay deterministic.

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Open a Pull Request

## License

MIT
