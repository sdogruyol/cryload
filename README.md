# cryload

[![CI](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml/badge.svg)](https://github.com/sdogruyol/cryload/actions/workflows/ci.yml)

HTTP benchmarking tool written in [Crystal](https://crystal-lang.org/).

## Installation

Requires Crystal `1.19.0` or later.

```bash
git clone https://github.com/sdogruyol/cryload.git && cd cryload
shards build --release
```

The binary will be at `bin/cryload`.

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
| `-h`, `--help` | Show help |

**Examples:**

```bash
# 10,000 requests to localhost
cryload http://localhost:9292 -n 10000

# 10 seconds with 100 connections
cryload http://localhost:3000 -d 10 -c 100
```

**Example output:**

```
Preparing to make it CRY for 10 seconds with 100 connections!
Running load test @ http://localhost:3000/

  Stats      Avg      Stdev    Max
  Latency    0.53ms   0.76ms   35.39ms

  1696170 requests in 10.11s
  Requests/sec:  167803.62
  2xx: 1696170    Non-2xx: 0
```

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Open a Pull Request

## License

MIT
