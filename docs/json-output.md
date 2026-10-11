# JSON output reference

Use `--json` or `--output-format json` to emit a single JSON document on stdout. Text progress and the human-readable summary are suppressed; stderr may still show progress when it is a TTY (`--no-progress` to disable).

Schema version: **1**.

Every key documented below is **always present**. Values are `null` when the key does not apply to the run, so consumers never have to probe for key existence. All latency values are milliseconds.

## Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | integer | JSON schema version. `1` for cryload 6.x. Bumped only on a breaking schema change |
| `cryload_version` | string | Release that produced the report, e.g. `"6.0.0"` |
| `url` | string | Target URL shown in the report (multi-URL runs use `http://first (+N more)`) |
| `duration_mode` | boolean | `true` when the run used `-d`, otherwise request-count mode |
| `config` | object | Effective run configuration |
| `summary` | object | Throughput and error-rate summary |
| `rate` | object | Rate-limit schedule attainment. Fields are `null` without `--rate` |
| `transfer` | object | Response body size metrics |
| `latency_ms` | object | Service-time latency aggregates |
| `corrected_latency_ms` | object | Coordinated-omission-corrected latency aggregates |
| `send_delay_ms` | object | Gap between scheduled and actual send time |
| `phases_ms` | object | Per-phase breakdown: dns, connect, tls, ttfb, total |
| `latency_histogram` | array | Rolled-up histogram buckets |
| `status` | object | HTTP success/failure breakdown |
| `by_status` | array | Per-HTTP-status-code breakdown with latency |
| `by_url` | array \| null | Per-URL breakdown. `null` for single-URL runs and for lists over 1000 URLs |
| `thresholds` | object | Every evaluated CI gate and its result |
| `verdict` | object | Final exit code and reason |

## `config`

| Field | Type | Description |
|-------|------|-------------|
| `workers` | integer | OS threads running the load fibers (`--workers`) |
| `connections` | integer | Concurrent connections (`-c`) |
| `rate_limit` | number \| null | Requested req/s (`--rate`), `null` when unlimited |
| `latency_correction` | boolean | `true` when threshold gates use corrected latency |
| `keepalive` | boolean | `false` when `--disable-keepalive` was used |
| `request_timeout_seconds` | number \| null | Total per-request deadline (`--request-timeout`) |
| `timeout_seconds` | number \| null | Connect/read/write timeout (`--timeout`) |

## `summary`

| Field | Type | Description |
|-------|------|-------------|
| `requests` | integer | Total attempts (responses + transport errors) |
| `responses` | integer | Completed HTTP responses |
| `transport_errors` | integer | Connection/TLS/IO failures |
| `elapsed_seconds` | number | Wall-clock benchmark duration |
| `requests_per_second` | number | `requests / elapsed_seconds` |
| `failure_rate_percent` | number | `(failed HTTP + transport errors) / requests * 100` |

## `rate`

Present only in a meaningful sense for rate-limited runs. Without `--rate` every field is `null` **except** `attained_per_second`, which always mirrors `summary.requests_per_second`.

| Field | Type | Description |
|-------|------|-------------|
| `requested_per_second` | number \| null | The `--rate` value |
| `attained_per_second` | number | Actually achieved req/s |
| `attainment_percent` | number \| null | `attained / requested * 100` |
| `scheduled_requests` | integer \| null | Schedule slots the run should have issued |
| `skipped_requests` | integer \| null | Slots that were never issued because the target could not keep up |
| `schedule_drift_ms` | number \| null | How far behind the schedule the run finished |

A non-zero `skipped_requests` means the reported uncorrected latency is optimistic. That is exactly the coordinated omission that `corrected_latency_ms` accounts for.

## `transfer`

| Field | Type | Description |
|-------|------|-------------|
| `total_bytes` | integer | Sum of response body bytes as received; a compressed body is counted compressed, not inflated |
| `size_per_request_bytes` | number | Average bytes per HTTP response |
| `bytes_per_second` | number | Throughput in bytes/sec |

## `latency_ms`

Service time: from the moment the request was actually written to the moment the response finished. Transport errors are excluded.

| Field | Description |
|-------|-------------|
| `avg`, `min`, `max`, `stdev` | Basic latency stats |
| `p10`, `p25`, `p50`, `p75`, `p90`, `p95`, `p99`, `p999` | Percentiles |

## `corrected_latency_ms`

Same keys as `latency_ms`. Reports send delay + service time, so a request that sat in the queue because the target stalled is charged for the wait it caused.

**`corrected_latency_ms` equals `latency_ms` when `--rate` is not used.** Without `--rate` there is no request schedule, so there is no send delay to correct for.

This is the object CI gates read by default (`--latency-correction on`). Use `--latency-correction off` to gate on `latency_ms` instead.

## `send_delay_ms`

How long each request waited between its scheduled send time and its actual send time. All zeros for an unrated run.

| Field | Description |
|-------|-------------|
| `avg`, `min`, `max`, `stdev` | Basic stats |
| `p50`, `p90`, `p99`, `p999` | Percentiles |

## `phases_ms`

One object per phase: `dns`, `connect`, `tls`, `ttfb`, `total`. Each has the same keys.

| Field | Type | Description |
|-------|------|-------------|
| `count` | integer | Number of samples for this phase (see below) |
| `avg`, `min`, `max` | number | Basic stats |
| `p50`, `p95`, `p99` | number | Percentiles |

**`dns`, `connect` and `tls` are per connection, not per request.** With keep-alive only the first request on a connection pays them, so their `count` is the number of connections opened — not the number of requests. `ttfb` and `total` are per response, so their `count` matches `summary.responses`.

`tls.count` is `0` for plain-HTTP targets.

Use `--disable-keepalive` to make every request pay setup cost, which moves `connect.count` up to the request count and folds setup into `latency_ms`.

## `latency_histogram[]`

| Field | Type | Description |
|-------|------|-------------|
| `start_ms` | number | Bucket start (inclusive) |
| `end_ms` | number | Bucket end |
| `count` | integer | Requests in bucket |
| `percent` | number | Share of total requests |

## `status`

| Field | Type | Description |
|-------|------|-------------|
| `success_statuses` | string[] | Configured success code ranges |
| `successful_count` | integer | Responses counted as success |
| `successful_percent` | number | Share of HTTP responses |
| `failed_count` | integer | HTTP responses outside success ranges |
| `failed_percent` | number | Share of HTTP responses |
| `transport_error_percent` | number | Share of all attempts |
| `codes[]` | array | `{ "code", "count", "percent" }` per HTTP status |
| `transport_errors[]` | array | `{ "category", "count", "percent", "sample_message" }` per error category |

### Transport error categories

`status.transport_errors[].category` is one of a fixed vocabulary:

`dns_failure`, `connect_refused`, `connect_timeout`, `connect_failed`, `read_timeout`, `write_timeout`, `request_timeout`, `connection_reset`, `connection_closed`, `tls_error`, `proxy_error`, `protocol_error`, `other`

`sample_message` carries one representative raw error string for debugging. Do not match on it; match on `category`.

## `by_status[]`

| Field | Type | Description |
|-------|------|-------------|
| `code` | integer | HTTP status code |
| `count` | integer | Responses with this code |
| `percent` | number | Share of HTTP responses |
| `avg_ms`, `p50_ms`, `p95_ms`, `p99_ms` | number | Latency for this code only |

Useful for spotting a fast-failing 503 path hiding behind an acceptable global p99.

## `by_url[]`

`null` when the run has a single target URL, and `null` when the target list has more than **1000** URLs (per-URL histograms would be wasteful at that size). An array otherwise.

| Field | Type | Description |
|-------|------|-------------|
| `url` | string | Target URL |
| `requests` | integer | Attempts against this URL |
| `responses` | integer | Completed responses |
| `transport_errors` | integer | Transport failures |
| `ok` | integer | Responses counted as success |
| `failed` | integer | Responses outside success ranges |
| `failure_rate_percent` | number | Failure share for this URL |
| `requests_per_second` | number | Throughput for this URL |
| `avg_ms`, `min_ms`, `max_ms` | number | Latency stats |
| `p50_ms`, `p95_ms`, `p99_ms` | number | Percentiles |

`--url-threshold` requires `by_url` to be active. Combining it with a target list over 1000 URLs is a config error (exit 2).

## `thresholds`

| Field | Type | Description |
|-------|------|-------------|
| `passed` | boolean | `true` when no configured gate was breached |
| `evaluated[]` | array | Every gate that ran, passing or not |
| `breached[]` | array | Subset of `evaluated[]` with `passed: false` |

Each entry of `evaluated[]` and `breached[]`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Flag name, e.g. `max-p99`, `min-rps`, `max-fail-rate` |
| `scope` | string | `global`, or the `--url-threshold` pattern for per-endpoint gates |
| `metric` | string | Metric actually compared, e.g. `corrected_p99` when correction is on |
| `comparator` | string | `<=` or `>=` |
| `limit` | number | Configured limit |
| `actual` | number | Observed value |
| `passed` | boolean | Gate result |

Read `metric` when a gate result surprises you: with `--latency-correction on` a `max-p99` gate reports `corrected_p99`, not `p99`.

## `verdict`

| Field | Type | Description |
|-------|------|-------------|
| `exit_code` | integer | `0`, `1`, `2`, `3`, `130` or `143` |
| `reason` | string | `ok`, `threshold_breached`, `target_unreachable`, `interrupted`, `terminated` |

## Migrating from the v5 schema

Added top-level keys:

| Key | Notes |
|-----|-------|
| `schema_version` | `1`. Gate your parser on this |
| `cryload_version` | Producing release |
| `config` | Effective run configuration, including `workers` |
| `rate` | Rate attainment. `null` fields without `--rate` |
| `corrected_latency_ms` | Coordinated-omission-corrected latency; equals `latency_ms` without `--rate` |
| `send_delay_ms` | Scheduled-vs-actual send gap |
| `phases_ms` | dns / connect / tls / ttfb / total |
| `by_status` | Per-status-code latency |
| `by_url` | Per-URL breakdown, `null` for single-URL and >1000-URL runs |
| `thresholds` | Evaluated CI gates |
| `verdict` | Exit code and reason |

Nothing was removed or renamed: every v5 key (`url`, `duration_mode`, `summary`, `transfer`, `latency_ms`, `latency_histogram`, `status`) keeps its name, type and meaning.

Changed values:

- `status.transport_errors[].category` no longer contains Crystal exception class names such as `IO::TimeoutError` or `Socket::ConnectError`. It now contains a normalized category from the fixed vocabulary listed above. A consumer matching on class names must be updated.
- A gate on `latency_ms.p99` in your own `jq` check still works, but cryload's own `--max-p99` now compares `corrected_latency_ms.p99` by default. Use `--latency-correction off` to restore v5 gate semantics.

## Example

```bash
cryload http://localhost:3000/api -n 500 --json > result.json
jq '.summary.requests, .latency_ms.p99, .status.successful_count' result.json
```

## CI checks

```bash
cryload http://localhost:3000/api -d 30s -q 500 --json > result.json

# Schema guard: fail loudly if a future cryload changes the shape
jq -e '.schema_version == 1' result.json

# Error budget
jq -e '.summary.failure_rate_percent <= 1' result.json

# Corrected p99 gate — the honest one. Uncorrected p99 can look fine
# while the target stalls and drops schedule slots.
jq -e '.corrected_latency_ms.p99 <= 250' result.json

# Rate attainment gate: the run must have actually achieved the rate it asked for
jq -e '.rate.attainment_percent >= 99' result.json
jq -e '.rate.skipped_requests == 0' result.json
```

Or let cryload do the gating and read the verdict:

```bash
cryload http://localhost:3000/api -d 30s -q 500 \
  --max-p99 250 --fail-on-rate-miss --json > result.json

# Which gate failed, and what did it actually compare?
jq -r '.thresholds.breached[] | "\(.name) \(.metric) \(.actual) > \(.limit)"' result.json
jq -r '.verdict | "exit \(.exit_code): \(.reason)"' result.json
```

Per-endpoint results on a multi-URL run:

```bash
cryload --urls-file urls.txt -d 30s --json > result.json
jq -r '.by_url[] | "\(.url) p99=\(.p99_ms) rps=\(.requests_per_second)"' result.json
```

Where did the latency go?

```bash
jq -r '.phases_ms | to_entries[] | "\(.key) count=\(.value.count) p95=\(.value.p95)"' result.json
```

Remember that `dns`/`connect`/`tls` counts are per connection, so a keep-alive run shows a handful of samples next to hundreds of thousands of `ttfb` samples.

See also [README](../README.md#cicd) for a GitHub Actions workflow example, and [docs/examples.md](examples.md) for a command cookbook.
