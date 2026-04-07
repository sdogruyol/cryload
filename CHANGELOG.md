# Unreleased

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
