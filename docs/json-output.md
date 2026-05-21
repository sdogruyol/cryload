# JSON output reference

Use `--json` or `--output-format json` to emit a single JSON document on stdout. Text progress and the human-readable summary are suppressed; stderr may still show progress unless `--no-progress` is set.

## Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `url` | string | Target URL shown in the report (multi-URL runs use `http://first (+N more)`) |
| `duration_mode` | boolean | `true` when the run used `-d`, otherwise request-count mode |
| `summary` | object | Throughput and error-rate summary |
| `transfer` | object | Response body size metrics |
| `latency_ms` | object | Latency aggregates in milliseconds |
| `latency_histogram` | array | Rolled-up histogram buckets |
| `status` | object | HTTP success/failure breakdown |

## `summary`

| Field | Type | Description |
|-------|------|-------------|
| `requests` | integer | Total attempts (responses + transport errors) |
| `responses` | integer | Completed HTTP responses |
| `transport_errors` | integer | Connection/TLS/IO failures |
| `elapsed_seconds` | number | Wall-clock benchmark duration |
| `requests_per_second` | number | `requests / elapsed_seconds` |
| `failure_rate_percent` | number | `(failed HTTP + transport errors) / requests * 100` |

## `transfer`

| Field | Type | Description |
|-------|------|-------------|
| `total_bytes` | integer | Sum of response body bytes |
| `size_per_request_bytes` | number | Average bytes per HTTP response |
| `bytes_per_second` | number | Throughput in bytes/sec |

## `latency_ms`

All values are in milliseconds.

| Field | Description |
|-------|-------------|
| `avg`, `min`, `max`, `stdev` | Basic latency stats |
| `p10`, `p25`, `p50`, `p75`, `p90`, `p95`, `p99`, `p999` | Percentiles |

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
| `transport_errors[]` | array | `{ "category", "count", "percent" }` per error class |

## Example

```bash
cryload http://localhost:3000/api -n 500 --json > result.json
jq '.summary.requests, .latency_ms.p99, .status.successful_count' result.json
```

## CI checks

```bash
cryload http://localhost:3000/api -n 1000 --json > result.json
jq -e '.summary.failure_rate_percent <= 1' result.json
jq -e '.latency_ms.p99 <= 250' result.json
```

See also [README](../README.md#json-output) for a GitHub Actions workflow example.
