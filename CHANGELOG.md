# Unreleased

- **Resilience** — Transport errors are now counted and reported instead of aborting the run on the first failed request
- **Reporting** — Added `p50`, `p90`, and `p999` percentiles plus response/error totals in final output
- **Diagnostics** — Added exact HTTP status code breakdowns and transport error counts to human and JSON output

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
