# Unreleased

- **Documentation** — Public descriptions match the README: honest latency and CI thresholds, no stale throughput number. `shard.yml`, the Docker image, `--help`, and the installers now share that positioning.
- **Reporting** — A refused connection is reported as `connect_refused` again when cryload is built with Crystal 1.21.1+. Crystal 1.21.1 (crystal-lang/crystal#17436) swapped the real connect error for a stale errno (`connect: Operation now in progress`), so refusals showed up as `connect_failed`. cryload patches the Unix event loops' `connect` until upstream ships the fix
- **Reporting** — A connect that exceeds `--timeout` is reported as `connect_timeout`. The stdlib raises a bare `IO::TimeoutError` for it, so it used to land in `read_timeout` and `connect_timeout` was never emitted
- **CLI** — Numeric flags reject `nan`, `inf` and out-of-range values with a config error (exit 2). `--rate inf`, `-d inf` or `--rate 1e-10` used to crash with `OverflowError`, and `--max-p99 nan` crashed with `JSON::Error` after the whole run, all exiting 1 — the threshold-breach code. `--rate` now needs at least `1e-9` requests/sec, and huge finite limits (`--max-p99 1e300`) render instead of overflowing
- **Proxy** — HTTPS targets through `--proxy` now honour `--timeout` on the tunnel (CONNECT reply, TLS handshake and every request; a stalled proxy used to block the worker forever), reconnect after the target closes a keep-alive connection instead of failing every later request as `other`, close the socket when CONNECT or the handshake fails, and support `https://` proxies and IPv6 proxy literals. Tunnel phases: `dns`/`connect` describe the proxy hop (`connect` includes the CONNECT exchange), `tls` the handshake with the target
- **Proxy** — Plain-HTTP targets through `--proxy http://user:pass@...` now send `Proxy-Authorization`; only the CONNECT tunnel used to carry the credentials
- **Accuracy** — Transfer metrics count response bodies as received. cryload still sends `Accept-Encoding: gzip, deflate` by default, but no longer inflates the body, so `transfer.*` and "Total data" report compressed bytes for a compressing target, and the generator spends no CPU on zlib. An explicit `-H Accept-Encoding` still wins
- **Accuracy** — The process exits with the exact code the report printed. The gates used to be evaluated again after the report was written, and in request-count mode the measurement window stayed open meanwhile, so a slow stdout reader could turn a printed `verdict.exit_code: 0` into exit 1 under `--min-rps`. The window now closes when the last request is merged

# 6.0.0 (29-08-2026)

- **Breaking (Concurrency)** — Multi-core load generation is now the default. v5 ran every load fiber on a single thread; v6 sizes the execution context to `min(cpu_count, connections)` OS threads and exposes it as `--workers N`. `--workers 1` reproduces the v5 single-core path; the cpu default respects `CRYSTAL_WORKERS`
- **Breaking (Accuracy)** — Threshold gates now evaluate **corrected** latency by default (`--latency-correction on`). A run that passed `--max-p99` in v5 can fail in v6 when the target could not keep up with `--rate`; corrected and uncorrected latency are identical when `--rate` is not set. Pass `--latency-correction off` for v5 gate semantics
- **Breaking (Exit codes)** — Exit codes are now a taxonomy instead of a single failure code: usage/config errors moved from `1` to `2`, an unreachable target (zero HTTP responses plus at least one transport error) moved from `1` to `3`, and signals now exit `130` (SIGINT) / `143` (SIGTERM) instead of `0`. `1` is reserved for breached thresholds, and a breached threshold takes precedence over a signal code

| Code | Meaning |
|---|---|
| 0 | Run finished, no threshold breached |
| 1 | A threshold was breached |
| 2 | Usage/config error |
| 3 | Target unreachable |
| 130 | Interrupted (SIGINT) |
| 143 | Terminated (SIGTERM) |

- **Breaking (Reporting)** — Transport error categories are a fixed, normalized vocabulary instead of Crystal exception class names: `dns_failure`, `connect_refused`, `connect_timeout`, `connect_failed`, `read_timeout`, `write_timeout`, `request_timeout`, `connection_reset`, `connection_closed`, `tls_error`, `proxy_error`, `protocol_error`, `other`. Consumers matching on `IO::TimeoutError` or `Socket::ConnectError` must switch to the new names
- **Breaking (JSON)** — JSON output gained a top-level `schema_version`, currently `1`. Every documented key is always present and is `null` when not applicable, so consumers can stop probing for key existence
- **Breaking (CLI)** — `--progress` now defaults to on only when stderr is a TTY, so CI logs are clean without passing `--no-progress`. Explicit `--progress` still forces it on
- **Breaking (Toolchain)** — Minimum Crystal is now **1.21.0** (was 1.19.0); multi-core load generation uses `Fiber::ExecutionContext.default.resize`
- **Performance** — `--workers 8 -c 128` reaches a median **329,440 req/s** against a `SO_REUSEPORT` target on loopback, versus **109,161 req/s** on the single-thread `--workers 1` path — a 3.0x gain (AMD Ryzen AI 9 465, 20 threads, 2-byte body, median of 5 three-second runs). `--workers 16` measures *slower* (280,079 req/s) than `--workers 8` on the same box, which is why the default is `min(cpu cores, connections)` rather than every core
- **Performance** — Response bodies are streamed through one fixed buffer per worker instead of being materialised as a `String`, so peak RSS no longer scales with response size: 22.9 MB at `--workers 8 -c 128` with 2-byte bodies, 12.9 MB at `--workers 8 -c 32` with 100 KB bodies
- **Accuracy** — Added coordinated-omission correction. v5 measured latency only from the moment a request was actually sent, so a stalled target made the numbers *look better*: in a regression test that froze the target for 1 second during `-q 500 -d 5`, v5 reported **p99 = 0.37 ms** while silently dropping 490 of 2500 scheduled requests. v6 reports the outage in `corrected_latency_ms.p99` and surfaces the loss as `rate.skipped_requests`
- **Accuracy** — Added a `rate` block reporting requested vs attained req/s, attainment percent, scheduled and skipped requests, and schedule drift, so a rate-limited run can no longer claim a rate it never achieved
- **Accuracy** — Added `send_delay_ms` percentiles, the gap between a request's scheduled send time and its actual send time
- **Accuracy** — `--timeout` now sets the **write** timeout as well as connect and read; v5 left writes unbounded
- **Accuracy** — `-q` / `--rate` accepts fractional rates (`-q 0.5`)
- **CI/CD** — Added a full threshold matrix: `--max-p50`, `--max-p75`, `--max-p90`, `--max-p95`, `--max-p999`, `--max-avg`, and `--max-latency` alongside the existing `--max-p99`
- **CI/CD** — Added `--min-rps N` to fail a build when throughput drops below a floor
- **CI/CD** — Added `--fail-on-rate-miss` to exit 1 when the attained rate is more than 1% below the requested `--rate`
- **CI/CD** — Added repeatable per-endpoint gates via `--url-threshold "PATTERN METRIC VALUE"`, where `PATTERN` is a substring matched against the target URLs and `METRIC` is one of `max-p50 max-p75 max-p90 max-p95 max-p99 max-p999 max-avg max-latency max-fail-rate min-rps`. A pattern matching no target URL is a config error (exit 2)

```bash
cryload --urls-file urls.txt -d 30 \
  --url-threshold "/api/users max-p99 120" \
  --url-threshold "/api/search max-p99 400" \
  --min-rps 2000
```

- **CI/CD** — JSON output gained a `thresholds` block listing every evaluated gate with its scope, metric, comparator, limit, actual value and pass state, plus a `verdict` block carrying the exit code and reason
- **Load testing** — `-d`/`--duration`, `--timeout` and `--warmup` accept duration units: `30`, `30s`, `2m`, `1h30m`, `500ms`. A bare number is still seconds
- **Observability** — Added a latency phase breakdown (`phases_ms`) for dns, connect, tls, ttfb and total, so a slow run can be attributed to handshake cost versus server think time. dns/connect/tls are per **connection**, so with keep-alive their `count` is the number of connections opened
- **Observability** — Added a per-status breakdown (`by_status`) with latency percentiles per HTTP status code, so error responses can be distinguished from slow successes
- **Observability** — Added a per-URL breakdown (`by_url`) for multi-URL runs, with per-endpoint throughput, failure rate and percentiles. It is `null` for single-URL runs and for target lists over 1000 URLs
- **Observability** — Text output header gained `Workers:`, `Latency correction:` and `Request timeout:` lines, and the report gained `Corrected Latency Percentiles`, `Rate`, `Latency Phases`, `Per-URL` and `Thresholds` blocks
- **Observability** — CSV output appends the new v6 columns after the existing v5 columns in their original order, so header-indexed consumers keep working unchanged
- **Resilience** — Added `--request-timeout DURATION`, a total wall-clock deadline for one request including body download. It catches slow-trickle responses that never trip the per-operation `--timeout` and reports them as `request_timeout`
- **Resilience** — Added a file-descriptor preflight: cryload checks `RLIMIT_NOFILE` (POSIX only) and raises the soft limit toward the hard limit when it is below `connections + 64`. If it still cannot get there, it exits 2 naming the current and required limits instead of failing mid-run with connect errors
- **Documentation** — Rewrote [docs/json-output.md](docs/json-output.md) for schema version 1, including every null-value rule and a v5 migration section
- **Documentation** — Added [docs/examples.md](docs/examples.md), a cookbook of runnable commands covering request modes, bodies, auth, multi-URL, rate limiting, phase diagnosis, CI gates and exit-code handling
- **Documentation** — README performance table replaced with measured numbers and a methodology note; the inconsistent `~50,000 req/sec` claim is gone, and a new **Honest latency** section explains coordinated omission
- **Documentation** — Updated [docs/comparison.md](docs/comparison.md) with rows for coordinated-omission correction, latency phase breakdown, per-URL/per-status breakdown, per-endpoint gates, exit code taxonomy and total request deadline

# 5.2.1 (11-08-2026)

- **GitHub Action** — Shortened the `action.yml` description to 117 characters; GitHub Marketplace rejects listings whose description is 125 characters or longer, which blocked publishing v5.2.0

# 5.2.0 (11-08-2026)

- **Distribution** — Added a Docker image at [`ghcr.io/sdogruyol/cryload`](https://github.com/sdogruyol/cryload/pkgs/container/cryload): multi-arch (amd64/arm64), ~9 MB Alpine runtime around the same fully static binary as the Linux release

```bash
docker run --rm ghcr.io/sdogruyol/cryload https://example.com -n 1000 -c 50
```

- **Distribution** — Added a composite GitHub Action so cryload runs in a workflow step with thresholds and JSON results as step outputs; every CLI flag is exposed as an input, and `uses: sdogruyol/cryload@v5` tracks the latest v5 release

```yaml
- uses: sdogruyol/cryload@v5
  with:
    url: http://127.0.0.1:3000/api
    requests: 500
    max_p99: "250"
```

- **Releases** — Windows release binaries are now linked statically; earlier builds dynamically linked the Crystal toolchain's DLLs and failed to start on machines without Crystal installed
- **Releases** — Release smoke tests now cover Windows, so a broken Windows binary fails the release instead of shipping
- **Installer** — `scripts/install.sh` uses `GITHUB_TOKEN` for the latest-release API lookup when set, avoiding the anonymous per-IP rate limit shared across hosted CI runners
- **Installer** — `GITHUB_URL` now also redirects the release API lookup, so enterprise mirrors query their own `/api/v3` endpoint and a mirror token is never sent to public GitHub
- **Documentation** — Added [docs/github-action.md](docs/github-action.md) with the full input/output reference and version-pinning rules

# 5.1.0 (01-08-2026)

- **Releases** — Linux release binaries are now fully static (musl/Alpine), so they run on any distro without matching glibc/OpenSSL versions
- **Releases** — macOS release binary now links OpenSSL statically; release smoke tests cover HTTPS
- **Resilience** — Static OpenSSL builds ignore the host `openssl.cnf` by default (`OPENSSL_CONF` → null device) so foreign crypto-policy configs cannot abort TLS
- **Resilience** — On macOS, TLS falls back to the system CA bundle (`/etc/ssl/cert.pem`) when the OpenSSL default cert path is missing
- **Documentation** — README rewritten for CI/CD positioning; added FAQ and moved the full comparison table to [docs/comparison.md](docs/comparison.md)
- **Packaging** — Updated `shard.yml` description for shard registries

# 5.0.0 (10-06-2026)

- **Breaking (CSV)** — Removed duplicate `latency_fastest_ms` and `latency_slowest_ms` columns; use `latency_min_ms` and `latency_max_ms`
- **Breaking (Accuracy)** — Transport errors are excluded from latency metrics (avg/min/max/stdev/percentiles/histogram), so connect failures and timeouts no longer skew percentiles; latency fields report 0 when no responses were received
- **Load testing** — Added `--disable-keepalive` to open a fresh connection per request (sends `Connection: close`), so connection setup cost is part of the measured latency
- **Request Ergonomics** — Added `--body-stdin` to read the request body from standard input (pipe-friendly)
- **Performance** — Latency histogram now uses HDR-style logarithmic buckets (~1% relative precision from 1µs to 1h) instead of a dense linear array, cutting memory from ~4.8 MB to ~18 KB; reported percentiles are accurate within 1%
- **Performance** — Duration mode now flushes worker stats in batches (250 requests or 1s) instead of sending one channel message per request
- **Performance** — `--random-path` and `--urls-file` now reuse one keep-alive client per origin instead of opening a new TCP/TLS connection per request
- **CLI** — Live progress is now time-based: a ticker refreshes the line every second regardless of throughput, so slow and rate-limited runs stay visible
- **CLI** — Invalid numeric flag values (e.g. `-n abc`, `--max-p99 zz`) now print a clear error and exit 1 instead of crashing with a stack trace
- **Refactor** — CLI options now use a typed `Cli::Options` class instead of a union-typed Hash with casts; ARGV is parsed once instead of twice
- **Documentation** — README comparison table now covers CI thresholds, keep-alive control, body sources, HTTP/2, and multi-core support; cryload's current HTTP/1.1 and single-core limits are stated explicitly

# 4.0.0 (21-05-2026)

- **Load testing** — Added `--warmup` to run untimed requests before the benchmark window
- **Load testing** — Added `--proxy` for HTTP and HTTPS targets through an HTTP(S) proxy (including CONNECT tunneling)
- **Load testing** — Added `--urls-file` for round-robin multi-URL targets; positional URL is optional when the file is provided
- **Load testing** — Added repeatable `--cookie` flags and `--random-path` for cache-busting path segments
- **CI/CD** — Added `--fail-on-error`, `--fail-on-transport-error`, `--max-fail-rate`, and `--max-p99` for pipeline-friendly exit codes
- **CI/CD** — JSON output uses a structured schema (`summary`, `latency_ms`, `status`); legacy duplicate keys removed
- **Performance** — Rate limiter now uses lock-free slot reservation instead of a global mutex
- **Performance** — Redirect hops drain response bodies and close cross-origin clients to improve connection reuse
- **Performance** — Duration mode freezes throughput timing at the deadline and drains late worker batches during a short grace window
- **Resilience** — Transport errors from any request exception are counted without aborting workers
- **CLI** — Live stderr progress is enabled by default (`--no-progress` to disable)
- **CLI** — Added `-V` / `--version` to print the installed release
- **Refactor** — Split monolithic source into focused modules under `src/cryload/`
- **Refactor** — Split CLI validation and option resolution into `Cli::Validator` and `Cli::OptionsBuilder`
- **Documentation** — README now documents exit codes, JSON fields, CI threshold examples, and a GitHub Actions workflow snippet
- **Documentation** — Added [docs/json-output.md](docs/json-output.md) JSON field reference
- **Releases** — GitHub Releases now include notes extracted from `CHANGELOG.md`
- **Tests** — Added unit specs for `Request` redirects, `Logger` JSON/CSV output, HTTPS `--insecure`, and CLI validation for proxy/cookie/warmup
- **Tests** — Spec helper rebuilds the binary when source files change
- **Architecture** — Single shutdown path via `ShutdownCoordinator` (one `log_final` + exit)
- **Tests** — Added live `--progress` stderr e2e and HTTP `--proxy` integration test
- **Releases** — Added Linux arm64 binary, post-build smoke tests, and install script arm64 detection

# 3.2.0 (18-04-2026)

- **Documentation** — README tagline and positioning now describe cryload as a cross-platform HTTP load testing CLI and a modern **ab** / **wrk** alternative with machine-readable **CI/CD** reports
- **CLI** — `--help` (and empty-invocation help) banner prefixed with the same one-line project description
- **Packaging** — `shard.yml` now includes a quoted `description` field for shard registries and discovery (YAML-safe when the text contains colons)

# 3.1.0 (07-04-2026)

- **Distribution** — Added `scripts/install.sh` for Linux, macOS, and Git Bash on Windows: downloads the release binary, verifies SHA256, and installs to `~/.local/bin` (configurable via `INSTALL_DIR`, `VERSION`, `REPO`)

```bash
curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
```

- **Distribution** — Added `scripts/install.ps1` for Windows PowerShell with the same checksum-verified install flow to `%USERPROFILE%\.local\bin`

```powershell
iwr -useb https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.ps1 | iex
```

- **Releases** — GitHub Release assets now include `.sha256` checksum files alongside each prebuilt binary (Linux, macOS, Windows)
- **Documentation** — README installation section documents the install scripts and ordering (script → manual binary → build from source)

# 3.0.0 (07-04-2026)

- **Request Ergonomics** — Added `--body-file` for reading request payloads from disk

```bash
cryload http://localhost:3000/api -n 500 -m POST -H "Content-Type: application/json" --body-file payload.json
```

- **Request Ergonomics** — Added `--basic-auth` / `-a` for Basic authentication

```bash
cryload http://localhost:3000/private -n 300 --basic-auth username:password
```

- **Request Ergonomics** — Added `--user-agent` for User-Agent overrides

```bash
cryload http://localhost:3000 -n 300 --user-agent cryload-test/1.0
```

- **Request Ergonomics** — Added `--host-header` for explicit Host header control

```bash
cryload http://127.0.0.1:3000 -n 300 --host-header api.internal
```

- **Request Ergonomics** — Added `-L` / `--follow-redirects` for redirect-aware benchmarking

```bash
cryload http://localhost:3000/redirect -n 100 -L
```

- **Output Modes** — Added `--output-format` with `text`, `json`, `csv`, and `quiet` modes while keeping `--json` as a compatibility shortcut

```bash
cryload http://localhost:3000/api -n 1000 --output-format csv
cryload http://localhost:3000/health -n 10 --output-format quiet
```

- **Success Criteria** — Added `--success-status` so custom HTTP codes/ranges can count as successful responses

```bash
cryload http://localhost:3000/redirect -n 100 --success-status 200-299,302
```

- **Reporting Polish** — Text/JSON/CSV reports now include minimum latency plus success/failure and transport error percentages
- **Reporting Polish** — Human-readable text output is now grouped into clearer header/summary/latency/status sections
- **Latency Visualization** — Added rolled-up response time histogram and distribution reporting in text/JSON output
- **Transfer Metrics** — Added total response data, size per request, and transfer per second reporting in text/JSON/CSV output
- **Status Breakdown** — Added richer status/error distribution reporting with counts and percentages in text/JSON/CSV output
- **Latency Naming** — Added `fastest` / `slowest` latency labels alongside `min` / `max` for easier comparison with `hey` / `oha`
- **Output Consistency** — Standardized section names and added normalized `summary`, `latency`, and `status` objects/headers across text/JSON/CSV output


# 2.3.0 (06-04-2026)

- **Resilience** — Transport errors are now counted and reported instead of aborting the run on the first failed request
- **Reporting** — Added `p50`, `p90`, and `p999` percentiles plus response/error totals in final output
- **Diagnostics** — Added exact HTTP status code breakdowns and transport error counts to human and JSON output
- **Traffic Shaping** — Added `--rate` / `-q` to cap total request throughput in requests per second
- **Performance** — Reduced hot-path coordination by batching worker-local metrics before merging them into global stats

# 2.2.0 (02-03-2026)

- Use `Process.on_terminate` to fix Windows build

# 2.1.0 (02-03-2026)

- **CLI Validation** — Standardized exit codes for help/errors and improved argument validation (`-n/-d`, URL, connections, timeout, headers, method)
- **Latency Metrics** — Added percentile reporting (`p95`, `p99`) with histogram-backed calculation
- **Output Modes** — Added `--json` output mode for automation/CI use cases
- **HTTP Features** — Added `--method`, `--body`, repeatable `--header`, and `--timeout` support
- **TLS** — Added `--insecure` to accept invalid certificates for HTTPS targets
- **Logging** — Improved terminal latency/percentile output formatting readability

# 2.0.0 (01-03-2026)

- **Crystal 1.19.0** — Minimum Crystal version updated from 1.0.0
- **CI** — Migrated from Travis CI to GitHub Actions
- **Build** — Use `shards build --release` instead of `crystal build`
- **CLI** — URL is now a positional argument (e.g. `cryload http://localhost:3000 -n 100`)

# 1.0.0 (22-03-2021)

- Crystal 1.0.0 support :tada:
