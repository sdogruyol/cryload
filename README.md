<p align="left">
  <img src="assets/logo.png" alt="cryload logo" width="180">
</p>

# cryload — HTTP load testing for CI/CD

Cross-platform, single-binary HTTP load testing CLI. Concurrent requests, latency percentiles, JSON/CSV output, and CI threshold gates. A modern alternative to `ab` / `wrk` / `hey`, written in Crystal.

[![CI](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml/badge.svg)](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sdogruyol/cryload)](https://github.com/sdogruyol/cryload/releases)
[![Downloads](https://img.shields.io/github/downloads/sdogruyol/cryload/total)](https://github.com/sdogruyol/cryload/releases)
![Crystal](https://img.shields.io/badge/Crystal-1.19+-%23000?logo=crystal)
[![License](https://img.shields.io/github/license/sdogruyol/cryload)](LICENSE)

---

## Quick start

```bash
curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh
cryload https://example.com -n 1000 -c 50
```

That's it. 1000 requests, 50 concurrent connections, JSON/CSV/plain output.

---

## Demo

```
$ cryload http://localhost:3000 -d 10 -c 100

Summary
  Requests/sec: 16155.06
  Total: 161551 requests in 10.0s
  Transport errors: 0 (0.0%)

Latency (ms)
  avg: 0.62   p50: 0.3   p95: 0.6   p99: 0.9   max: 2043.1

Status
  ✅ 161551 (100.0%) — 200
```

---

## Features

- **Concurrent** load with configurable connection count (`-c`)
- **Duration** (`-d`) or **request count** (`-n`) mode
- **Latency percentiles**: p50, p75, p90, p95, p99, p999 + histogram
- **CI/CD ready**: JSON, CSV, quiet output modes
- **CI thresholds**: `--max-p99`, `--max-fail-rate`, `--fail-on-error` exit codes
- **Rate limiting**: `--rate` for global RPS cap
- **Flexible requests**: method, headers, body (string/file/stdin), auth, cookies, proxy
- **Redirects**: follow (`-L`) or custom success status codes
- **Warmup phase**, **keep-alive** control, **TLS** skip
- **Multi-URL**: load targets from file
- **Cross-platform**: Linux, macOS, Windows — single binary each

---

## Installation

### Option 1: Install script (recommended)

Downloads the matching release asset, verifies SHA256, installs to `~/.local/bin`.

**Linux / macOS:**

```bash
curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

Specific version:

```bash
VERSION=v5.0.0 curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

**Windows (PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.ps1 | iex
```

### Option 2: Prebuilt binary

Download from [Releases](https://github.com/sdogruyol/cryload/releases):

```bash
chmod +x cryload-linux
./cryload-linux --help
```

Assets: `cryload-linux`, `cryload-linux-arm64`, `cryload-macos`, `cryload-windows.exe`.

### Option 3: Build from source

Requires Crystal >= 1.19.0.

```bash
git clone https://github.com/sdogruyol/cryload.git && cd cryload
shards build --release
# binary at bin/cryload
```

---

## Usage

```bash
cryload <url> [options]
```

| Option | Description |
|--------|-------------|
| `-n`, `--numbers` | Number of requests |
| `-d`, `--duration` | Test duration in seconds |
| `-c`, `--connections` | Concurrent connections (default: 10) |
| `-m`, `--method` | HTTP method (default: GET) |
| `-b`, `--body` | Request body |
| `--body-file` | Read body from file |
| `--body-stdin` | Read body from stdin |
| `-H`, `--header` | Repeatable header (`-H "Key: Value"`) |
| `--user-agent` | Set User-Agent |
| `--host-header` | Override Host header |
| `-a`, `--basic-auth` | Basic auth (`user:password`) |
| `--timeout` | Connect/read timeout in seconds |
| `-q`, `--rate` | Rate limit (req/sec) |
| `-L`, `--follow-redirects` | Follow redirects (up to 5 hops) |
| `--disable-keepalive` | New connection per request |
| `--output-format` | `text`, `json`, `csv`, `quiet` |
| `--success-status` | Custom success codes/ranges |
| `--insecure` | Skip TLS verification |
| `--warmup` | Warmup seconds before benchmark |
| `--proxy` | HTTP(S) proxy |
| `--cookie` | Repeatable cookie (`name=value`) |
| `--urls-file` | Load target URLs from file |
| `--random-path` | Append random path per request |
| `--no-progress` | Disable live progress |
| `-V`, `--version` | Print version |
| `-h`, `--help` | Show help |

### Common examples

```bash
# 10K requests, 100 concurrent
cryload http://localhost:3000 -n 10000 -c 100

# 30 seconds, 50 connections
cryload http://localhost:3000 -d 30 -c 50

# POST with JSON body
cryload http://localhost:3000/api -n 500 -m POST \
  -H "Content-Type: application/json" \
  -b '{"name":"cry"}' --timeout 5

# POST body from file
cryload http://localhost:3000/api -n 500 -m POST \
  -H "Content-Type: application/json" --body-file payload.json

# POST body from stdin (pipe-friendly)
jq -c '.payload' fixture.json | cryload http://localhost:3000/api \
  -n 500 -m POST -H "Content-Type: application/json" --body-stdin

# Rate-limited: 100 req/sec
cryload http://localhost:3000/api -n 1000 -c 50 --rate 100

# With warmup + proxy
cryload https://api.example.com -d 30 -c 50 --warmup 5 \
  --proxy http://user:pass@proxy.example.com:8080

# Session cookies + cache busting
cryload http://localhost:3000/api -n 1000 \
  --cookie session=abc123 --cookie theme=dark --random-path

# Measure connection setup cost (no keep-alive)
cryload http://localhost:3000/api -n 1000 --disable-keepalive
```

---

## CI/CD

cryload is built for pipelines. Use `--json` or `--output-format csv` for structured output, `--output-format quiet` for exit-code-only checks.

### Exit codes

| Code | When |
|------|------|
| `0` | All thresholds passed |
| `1` | Validation error or threshold violation |

### CI thresholds

| Flag | Effect |
|------|--------|
| `--fail-on-error` | Exit 1 on any HTTP/transport error |
| `--fail-on-transport-error` | Exit 1 on any transport error |
| `--max-fail-rate 5` | Exit 1 if failure rate > 5% |
| `--max-p99 200` | Exit 1 if p99 > 200 ms |

### GitHub Actions example

```yaml
- name: Install cryload
  run: curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s

- name: Smoke test
  run: cryload http://localhost:3000/health -n 100 --fail-on-error --output-format quiet

- name: Latency SLA
  run: |
    cryload http://localhost:3000/api -n 500 --max-p99 250 --json > result.json
    jq -e '.summary.failure_rate_percent <= 1' result.json
    jq -e '.latency_ms.p99 <= 250' result.json
```

### JSON output

`--json` emits structured output with `summary`, `transfer`, `latency_ms`, `latency_histogram`, and `status` sections. Full field reference: [docs/json-output.md](docs/json-output.md).

---

## How cryload compares

| Feature | cryload | ab | hey | wrk |
|---------|:-------:|:--:|:---:|:---:|
| **CI/CD output** (JSON/CSV/quiet) | ✅ | — | JSON | — |
| **CI threshold exit codes** | ✅ | — | — | — |
| **Rate limiting** (`--rate`) | ✅ | — | partial | — |
| **Redirects + custom success codes** | ✅ | — | partial | — |
| **Cross-platform binary** | ✅ | Linux | ✅ | Linux |
| **Multi-core load** | — | — | ✅ | ✅ |
| **HTTP/2** | — | — | ✅ | — |

Full comparison with `oha` and feature matrix: [docs/comparison.md](docs/comparison.md).

---

## Built with Crystal

cryload is written in [Crystal](https://crystal-lang.org/) — Ruby-like syntax, compiled speed, single-binary deployment.

---

## Contributing

1. Fork & branch (`git checkout -b my-feature`)
2. Commit (`git commit -am 'Add feature'`)
3. Push & open a PR

---

## License

MIT