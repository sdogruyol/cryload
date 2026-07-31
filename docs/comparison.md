# cryload comparison
Full feature comparison with other HTTP load testing tools.
| Feature | cryload | [ab](https://httpd.apache.org/docs/current/programs/ab.html) | [hey](https://github.com/rakyll/hey) | [oha](https://github.com/hatoo/oha) | [wrk](https://github.com/wg/wrk) |
|---------|:-------:|:--:|:---:|:---:|:--:|
| Language | Crystal | C | Go | Rust | C |
| **Concurrent** connections (`-c`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Duration** / **request count** (`-n`) | ✅ | ✅ (`-t` / `-n`) | ✅ | ✅ | ✅ |
| **JSON** / **CSV** / quiet output for **CI/CD** | ✅ | — (text) | JSON | JSON | — (text / Lua) |
| **CI thresholds** via exit codes (`--max-p99`, `--fail-on-error`) | ✅ | — | — | — | — |
| Text latency **histogram** + distribution | ✅ | basic | limited | TUI-focused | basic |
| Global **RPS cap** (`--rate`) | ✅ | — | per-worker (`-q`) | ✅ | different model |
| **Warmup**, **proxy**, **cookies**, multi-URL file | ✅ | — | partial | partial | — |
| **Follow redirects**, custom **success** HTTP codes | ✅ | — | partial | partial | — |
| **No keep-alive** mode (`--disable-keepalive`) | ✅ | default (enable with `-k`) | ✅ | ✅ (HTTP/1.1) | via Lua |
| **Body** from string / file / stdin | ✅ / ✅ / ✅ | file (`-p`) | ✅ / ✅ / — | ✅ / ✅ / — | via Lua |
| **HTTP/2** | — (HTTP/1.1) | — | ✅ (`-h2`) | ✅ (`--http2`) | — |
| **Multi-core** load generation | — (single-core) | — | ✅ (`-cpus`) | ✅ | ✅ (`-t`) |
| **Scriptable** load (Lua, etc.) | — | — | — | — | ✅ |
| **Cross-platform** binary | ✅ (Linux, macOS, Windows) | Linux | ✅ | ✅ | Linux |
## Which tool should I use?
**Choose wrk** when you need Lua-driven scenarios, multi-core saturation, and maximum tuning on Linux.
**Choose ab** when the classic Apache Bench one-liner is enough — plain-text summaries, GET-heavy checks, and httpd-family packages already on the machine.
**Choose hey or oha** when you need HTTP/2 or want to saturate every core of the load-generating machine.
**Choose cryload** when you want JSON/CSV reporting, CI threshold exit codes, rate limits, redirect handling, and histogram-style summaries in one cross-platform binary.
---
*Last updated: 2026-07-31*