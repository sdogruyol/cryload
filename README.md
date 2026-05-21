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
| **Warmup**, **proxy**, **cookies**, multi-URL file | ✓ | — | partial | partial | — |
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
- Warmup phase, HTTP(S) proxy, session cookies, multi-URL targets, and cache-busting random paths
- Live progress updates on stderr during text output (disable with `--no-progress`)

## Installation

### Option 1: Install script (recommended)

Downloads the matching asset from [Releases](https://github.com/sdogruyol/cryload/releases), verifies SHA256, and installs to `~/.local/bin` (or `%USERPROFILE%\.local\bin` on Windows).

**Linux / macOS** (needs `curl` or `wget`, and `sha256sum` or `shasum`):

```bash
curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

Install a specific version:

```bash
VERSION=v4.0.0 curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

**Windows** (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.ps1 | iex
```

### Option 2: Prebuilt binary

Download the matching asset from the [Releases page](https://github.com/sdogruyol/cryload/releases) (`cryload-linux`, `cryload-linux-arm64`, `cryload-macos`, or `cryload-windows.exe`).

**Linux:**

```bash
chmod +x cryload-linux
./cryload-linux --help
```

**macOS:** Same as Linux, using the `cryload-macos` binary.

**Windows** (PowerShell or Command Prompt, from the directory containing the file):

```powershell
.\cryload-windows.exe --help
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
| `--fail-on-error` | Exit with code 1 when any HTTP or transport error occurs |
| `--fail-on-transport-error` | Exit with code 1 when any transport error occurs |
| `--max-fail-rate` | Exit with code 1 when failure rate exceeds PERCENT |
| `--max-p99` | Exit with code 1 when p99 latency exceeds MS milliseconds |
| `--warmup` | Warm up before the timed benchmark (seconds) |
| `--proxy` | HTTP(S) proxy (`http://host:port` or `http://user:pass@host:port`) |
| `--no-progress` | Disable live progress on stderr |
| `--progress` | Show live progress on stderr during the run (default) |
| `--cookie` | Cookie value, repeatable (`name=value`) |
| `--urls-file` | Load target URLs from file (one http(s) URL per line) |
| `--random-path` | Append a random path segment to each request URL |
| `-V`, `--version` | Print version |
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

Warmup before the timed benchmark
```bash
cryload http://localhost:3000 -d 30 -c 50 --warmup 5
```

HTTP(S) proxy
```bash
cryload http://localhost:3000 -n 100 --proxy http://127.0.0.1:8080
cryload https://api.example.com -n 100 --proxy http://user:pass@proxy.example.com:8080
```

Session cookies (repeatable)
```bash
cryload http://localhost:3000/api -n 100 --cookie session=abc123 --cookie theme=dark
```

Multiple URLs from file (positional URL optional)
```bash
cryload --urls-file targets.txt -n 1000 -c 50
```

Cache-busting random path on each request
```bash
cryload http://localhost:3000/api -n 500 --random-path
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

CI failure thresholds
```bash
cryload http://localhost:3000/api -n 1000 --fail-on-error
cryload http://localhost:3000/api -n 1000 --max-fail-rate 5
cryload http://localhost:3000/api -n 1000 --max-p99 200
```

Print version
```bash
cryload --version
```

**Example output** (_sample run: `-d 10 -c 10` against a local server with a 13-byte body_):

```
Preparing to make it CRY for 10 seconds with 10 connections!
Running load test @ http://127.0.0.1:3000
Mode: duration (10s)
Connections: 10
Rate limit: unlimited
Warmup: none
Success statuses: 200-299

Summary
  Total requests: 161551
  Total time: 10.0s
  Requests/sec: 16155.06
  Responses: 161551
  Transport errors: 0 (0.0%)
  Fastest: 0.1 ms
  Slowest: 2043.12 ms

Status
  Successful: 161551 (100.0%)
  Failed: 0 (0.0%)
  Success statuses: 200-299

Transfer
  Total data: 2.0 MiB
  Size/request: 13.0 B
  Transfer/sec: 205.09 KiB/s

Latency (ms)
  avg: 0.62   min: 0.1   stdev: 16.71   max: 2043.1

Latency Percentiles (ms)
  p50: 0.3   p90: 0.5   p95: 0.6
  p99: 0.9   p999: 1.4

Latency Histogram (ms)
   185.8 ms [161512] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
   371.6 ms [0] |
   557.3 ms [0] |
   743.0 ms [0] |
   928.8 ms [0] |
  1114.5 ms [35] |■
  1300.2 ms [3] |■
  1485.9 ms [0] |
  1671.7 ms [0] |
  1857.4 ms [0] |
  2043.1 ms [1] |■

Latency Distribution (ms)
  10.0% in 0.1
  25.0% in 0.2
  50.0% in 0.3
  75.0% in 0.4
  90.0% in 0.5
  95.0% in 0.6
  99.0% in 0.9
  99.9% in 1.4


Status Code Distribution
  [200] 161551 responses (100.0%)
```

## Built With Crystal

cryload is written in [Crystal](https://crystal-lang.org/), combining Ruby-like developer ergonomics with compiled-language speed.

## Automation and CI

Use **`--json`** or **`--output-format csv`** for scripts, dashboards, and **GitHub Actions** jobs: parse a single structured summary instead of scraping text. Combine with **`-n`** for fixed request counts so pipelines stay deterministic.

### Exit codes

| Code | When |
|------|------|
| `0` | Run completed and all configured thresholds passed |
| `1` | Validation/usage error, or a CI threshold failed |

**Default failure behavior:** exit `1` only when every request is a transport error (no HTTP responses received).

**Optional CI thresholds** (combine as needed; any violation exits `1`):

| Flag | Effect |
|------|--------|
| `--fail-on-error` | Fail on any HTTP failure or transport error |
| `--fail-on-transport-error` | Fail on any transport error, even if some requests succeed |
| `--max-fail-rate 5` | Fail when `(HTTP failures + transport errors) / total requests` exceeds 5% |
| `--max-p99 200` | Fail when p99 latency exceeds 200 ms |

**Examples:**

```bash
# Smoke test: any 4xx/5xx or connection error fails the job
cryload http://localhost:3000/health -n 50 --fail-on-error --output-format quiet

# SLA gate: p99 must stay under 200 ms, failure rate under 1%
cryload http://localhost:3000/api -n 1000 --max-p99 200 --max-fail-rate 1 --output-format quiet
```

### JSON output

`--json` / `--output-format json` emits structured JSON with these sections:

| Section | Fields |
|---------|--------|
| `summary` | `requests`, `responses`, `transport_errors`, `elapsed_seconds`, `requests_per_second`, `failure_rate_percent` |
| `transfer` | `total_bytes`, `size_per_request_bytes`, `bytes_per_second` (response body only) |
| `latency_ms` | `avg`, `min`, `max`, `stdev`, `p10`, `p25`, `p50`, `p75`, `p90`, `p95`, `p99`, `p999` |
| `latency_histogram[]` | `start_ms`, `end_ms`, `count`, `percent` |
| `status` | `success_statuses`, `successful_count`, `successful_percent`, `failed_count`, `failed_percent`, `transport_error_percent`, `codes[]`, `transport_errors[]` |

Also includes top-level `url` and `duration_mode`. Full field reference: [docs/json-output.md](docs/json-output.md).

### GitHub Actions example

```yaml
- name: Install cryload
  run: curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s

- name: Verify binary
  run: cryload --version

- name: Smoke test API
  run: |
    cryload http://localhost:3000/health -n 100 --fail-on-error --output-format quiet

- name: Latency SLA check
  run: |
    cryload http://localhost:3000/api -n 500 --max-p99 250 --json > result.json
    jq -e '.summary.failure_rate_percent <= 1' result.json
    jq -e '.latency_ms.p99 <= 250' result.json
```

**Note:** `--output-format quiet` suppresses report output; combine with threshold flags when you only need pass/fail from the exit code.

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Open a Pull Request

## License

MIT
