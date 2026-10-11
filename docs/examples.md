# cryload examples

A cookbook. Every command is runnable as-is against a local server on port 3000.

Full field reference: [docs/json-output.md](json-output.md). Flag list: `cryload --help`.

## Duration syntax

`-d`, `--timeout`, `--request-timeout` and `--warmup` accept units. A bare number means seconds.

| Value | Meaning |
|-------|---------|
| `30` | 30 seconds |
| `30s` | 30 seconds |
| `2m` | 2 minutes |
| `1h30m` | 90 minutes |
| `500ms` | half a second |

---

## Quick smoke test

```bash
cryload http://localhost:3000/health -n 100 -c 10
```

100 requests over 10 connections. Fastest way to confirm the target is up, returns the status you expect, and is not pathologically slow. Exit code is `3` if nothing answered at all.

## Request-count mode vs duration mode

```bash
# Count mode: exactly 10,000 requests, however long that takes
cryload http://localhost:3000 -n 10000 -c 100

# Duration mode: as many requests as fit in 30 seconds
cryload http://localhost:3000 -d 30s -c 100
```

Count mode is what you want in CI: identical work every run, so latency numbers are comparable across builds. Duration mode is what you want when measuring capacity, since it reports the throughput ceiling. `duration_mode` in the JSON tells you which one produced a report.

## POST with a JSON body

```bash
# From a string
cryload http://localhost:3000/api/users -n 500 -m POST \
  -H "Content-Type: application/json" \
  -b '{"name":"cry","email":"cry@example.com"}'

# From a file
cryload http://localhost:3000/api/users -n 500 -m POST \
  -H "Content-Type: application/json" \
  --body-file payload.json

# From stdin — composes with anything that generates a payload
jq -n '{name: "cry", ts: now}' | cryload http://localhost:3000/api/users \
  -n 500 -m POST -H "Content-Type: application/json" --body-stdin
```

All three send the same bytes. `--body-stdin` reads once and reuses the payload for every request, so piping a generator does not produce distinct bodies per request.

## Headers, basic auth, cookies

```bash
cryload http://localhost:3000/api/private -n 300 \
  -H "Accept: application/json" \
  -H "X-Request-Source: cryload" \
  -a admin:s3cret \
  --cookie "session=abc123" \
  --cookie "feature_flag=on" \
  --user-agent "cryload-ci/1.0"
```

`-H`, `--cookie` are repeatable. `-a` sets the `Authorization: Basic` header for you. Use `--host-header` when you need to hit an IP but present a virtual host:

```bash
cryload http://127.0.0.1:3000/ -n 300 --host-header api.internal
```

## Multi-URL runs and the `by_url` block

```bash
cat > urls.txt <<'EOF'
http://localhost:3000/api/users
http://localhost:3000/api/search?q=crystal
http://localhost:3000/api/orders
EOF

cryload --urls-file urls.txt -d 30s -c 50 --json > result.json
jq -r '.by_url[] | "\(.url)\tp99=\(.p99_ms)ms\trps=\(.requests_per_second)\tfail=\(.failure_rate_percent)%"' result.json
```

URLs are used round-robin, so each endpoint gets an equal share of the load. The `by_url` block gives you per-endpoint throughput, failure rate and percentiles — that is how you find the one slow endpoint that a global p99 hides. `by_url` is `null` for single-URL runs and for lists over 1000 URLs.

## Cache-busting with `--random-path`

```bash
cryload http://localhost:3000/api/items -n 5000 -c 50 --random-path
```

Appends a random path segment per request so every request misses any CDN, reverse-proxy or application cache. Use this when you want to measure the origin, not the cache. Compare against the same run without the flag to see how much your cache is actually saving.

## Rate-limited (constant arrival rate) runs

```bash
cryload http://localhost:3000/api -d 60s -q 500 -c 100 --json > result.json
jq '.rate' result.json
```

`-q 500` schedules 500 requests per second regardless of how fast the target answers — a constant arrival rate, which is how real traffic behaves. Then check whether the target kept up:

```bash
jq -r '.rate | "requested=\(.requested_per_second) attained=\(.attained_per_second) \(.attainment_percent)% skipped=\(.skipped_requests)"' result.json
```

`rate.attainment_percent` below 100 means the load generator could not issue everything it scheduled because the target was stalling. `rate.skipped_requests` counts the slots that never went out. Both are the tell-tale signs that uncorrected latency is understating the problem — read `corrected_latency_ms` instead:

```bash
jq '.latency_ms.p99, .corrected_latency_ms.p99' result.json
```

Fractional rates work too, for long soak tests of low-traffic endpoints:

```bash
cryload http://localhost:3000/api/report -d 1h30m -q 0.5
```

## Diagnosing where the latency went

```bash
cryload https://api.example.com/v1/items -d 30s -c 50 --json > result.json
jq -r '.phases_ms | to_entries[] | "\(.key)\tcount=\(.value.count)\tp50=\(.value.p50)\tp95=\(.value.p95)"' result.json
```

Five phases: `dns`, `connect`, `tls`, `ttfb`, `total`. A high `tls.p95` with a low `ttfb.p95` means you are paying for handshakes, not for server work; the fix is connection reuse or session resumption, not application tuning. A low `tls` with a high `ttfb` means the server is thinking, and the application is where to look.

`dns`, `connect` and `tls` are measured **per connection**, so with keep-alive their `count` is the number of connections opened, not the number of requests. Seeing `connect.count = 50` next to `ttfb.count = 400000` is correct, not a bug.

## Include connection setup in every measurement

```bash
# Keep-alive on (default): setup amortized across the run
cryload https://api.example.com/v1/items -n 2000 -c 50

# Keep-alive off: every request pays DNS + connect + TLS
cryload https://api.example.com/v1/items -n 2000 -c 50 --disable-keepalive
```

`--disable-keepalive` sends `Connection: close` and opens a fresh connection per request, so setup cost lands inside `latency_ms`. Use it to model clients that cannot reuse connections, and to size the gap between best-case and cold-start latency.

## Warm up before the timed window

```bash
cryload http://localhost:3000/api -d 60s -c 100 --warmup 10s
```

Runs 10 seconds of untimed traffic first, then starts measuring. This keeps JIT warmup, lazy connection pools, cold caches and first-request compilation out of your percentiles. Anything with a JVM or a cold database connection pool on the other end needs this.

## Through a proxy

```bash
cryload https://api.example.com/v1/items -n 1000 --proxy http://proxy.internal:8080
```

Works for HTTP and HTTPS targets; HTTPS uses `CONNECT` tunneling through the proxy. Credentials in the proxy URL (`http://user:pass@proxy.internal:8080`) are sent as `Proxy-Authorization`. Proxy-layer failures report as the `proxy_error` category.

## Self-signed / internal TLS

```bash
cryload https://staging.internal:8443/health -n 500 --insecure
```

Skips certificate verification. For staging environments with internal CAs — never for measuring anything you care about the security of.

## Saturating multiple cores

```bash
# Default: min(cpu_count, connections) worker threads
cryload http://localhost:3000 -d 5s -c 128

# Pin the worker count explicitly
cryload http://localhost:3000 -d 5s -c 128 --workers 8

# Reproduce single-core (v5) behaviour
cryload http://localhost:3000 -d 5s -c 128 --workers 1
```

`--workers` sets how many OS threads run the load fibers. On a fast local target this is the difference between one core's throughput ceiling and the machine's. Compare the `requests_per_second` of `--workers 1` against `--workers 8` to find out whether you are measuring your server or your load generator — if throughput scales with workers, the load generator was the bottleneck and your earlier numbers were about cryload, not the target.

Also raise `-c`: workers default to `min(cpu_count, connections)`, so `-c 4 --workers 16` still gives you 4 workers.

## CI gates

Any breached gate exits `1`.

```bash
# Global latency + error budget
cryload http://localhost:3000/api -n 2000 -c 50 \
  --max-p95 120 \
  --max-p99 250 \
  --max-latency 2000 \
  --max-fail-rate 1 \
  --output-format quiet

# Throughput floor: fail if the build got slower under load
cryload http://localhost:3000/api -d 30s -c 100 --min-rps 5000

# Per-endpoint gates on a multi-URL run
cryload --urls-file urls.txt -d 30s -c 50 \
  --url-threshold "/api/users max-p99 120" \
  --url-threshold "/api/search max-p99 400" \
  --url-threshold "/api/orders max-fail-rate 0.5" \
  --url-threshold "/api/users min-rps 500"

# Rate-limited SLO: the target must sustain 500 req/s at p99 <= 250ms
cryload http://localhost:3000/api -d 60s -q 500 -c 100 \
  --max-p99 250 --fail-on-rate-miss
```

The full threshold matrix is `--max-p50`, `--max-p75`, `--max-p90`, `--max-p95`, `--max-p99`, `--max-p999`, `--max-avg`, `--max-latency`, `--max-fail-rate`, `--min-rps`. `--url-threshold "PATTERN METRIC VALUE"` takes any of `max-p50 max-p75 max-p90 max-p95 max-p99 max-p999 max-avg max-latency max-fail-rate min-rps` and matches `PATTERN` as a substring against the target URLs. A pattern that matches no target URL is a config error (exit `2`), so a renamed endpoint fails the build instead of silently un-gating it.

`--fail-on-rate-miss` fails when the attained rate is more than 1% below the requested `--rate`. Pair it with `--max-p99`: a target that keeps latency low by dropping load should not pass.

By default latency gates evaluate **corrected** latency. For v5 gate semantics:

```bash
cryload http://localhost:3000/api -d 30s -q 500 --max-p99 250 --latency-correction off
```

## Bounding a slow target

```bash
# Per-operation timeout: connect, read and write each get 5s
cryload http://localhost:3000/api -n 1000 --timeout 5s

# Total deadline for one request, including body download
cryload http://localhost:3000/large -n 1000 --timeout 5s --request-timeout 30s
```

`--timeout` bounds individual socket operations, so a response that trickles a byte every second never trips it. `--request-timeout` is a wall-clock deadline for the whole request and does catch that; those failures report as the `request_timeout` category.

## Parsing the output

JSON with `jq`:

```bash
cryload http://localhost:3000/api -n 1000 --json > result.json

jq -e '.schema_version == 1' result.json
jq -r '"p50=\(.latency_ms.p50) p99=\(.latency_ms.p99) rps=\(.summary.requests_per_second)"' result.json
jq -r '.status.codes[] | "\(.code)\t\(.count)\t\(.percent)%"' result.json
jq -r '.status.transport_errors[] | "\(.category)\t\(.count)"' result.json
jq -r '.by_status[] | "\(.code)\tp99=\(.p99_ms)ms"' result.json
jq -r '.thresholds.breached[] | "FAIL \(.name) \(.metric)=\(.actual) limit=\(.limit)"' result.json
```

CSV with `awk` — the header is a single row, so index by name once:

```bash
cryload http://localhost:3000/api -n 1000 --output-format csv > result.csv

awk -F, 'NR==1 { for (i=1; i<=NF; i++) c[$i]=i; next }
         { printf "p99=%s corrected_p99=%s exit=%s\n",
             $c["latency_p99_ms"], $c["latency_corrected_p99_ms"], $c["exit_code"] }' result.csv
```

v6 appends its new columns after the v5 columns and keeps the v5 order, so a header-indexed reader like the above keeps working across the upgrade. Positional readers do not need changes either, as long as they only read the leading v5 columns.

Append runs to one file for a trend line:

```bash
cryload http://localhost:3000/api -n 1000 --output-format csv | tail -n +2 >> history.csv
```

## Exit-code handling in a shell script

```bash
#!/usr/bin/env bash
set -uo pipefail

cryload http://localhost:3000/api -d 30s -c 50 \
  --max-p99 250 --min-rps 1000 --json > result.json
code=$?

case $code in
  0)
    echo "PASS: all thresholds met"
    ;;
  1)
    echo "FAIL: threshold breached"
    jq -r '.thresholds.breached[] | "  \(.name) \(.metric)=\(.actual) limit=\(.limit)"' result.json
    ;;
  2)
    echo "ERROR: usage or config problem — bad flag, bad URL, missing file,"
    echo "       an --url-threshold pattern that matched no target, or fd limit too low"
    ;;
  3)
    echo "ERROR: target unreachable — no HTTP response at all"
    jq -r '.status.transport_errors[] | "  \(.category): \(.sample_message)"' result.json
    ;;
  130)
    echo "ABORTED: interrupted (SIGINT)"
    ;;
  143)
    echo "ABORTED: terminated (SIGTERM)"
    ;;
  *)
    echo "UNEXPECTED exit code $code"
    ;;
esac

exit $code
```

Six distinct codes let a pipeline tell "the service got slower" (`1`, a real regression to triage) apart from "the service never came up" (`3`, a broken test harness) and "my command line is wrong" (`2`, a broken workflow file). v5 returned `1` for all of them. The same information is in the report as `verdict.exit_code` and `verdict.reason`.

Note that `set -e` would abort before the `case`, which is why the script above uses `set -uo pipefail` and captures `$?` explicitly.
