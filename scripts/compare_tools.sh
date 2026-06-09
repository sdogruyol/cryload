#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRYLOAD="${CRYLOAD:-$ROOT/bin/cryload}"
HEY="${HEY:-hey}"
WRK="${WRK:-wrk}"
DURATION="${DURATION:-10}"
CONNECTIONS="${CONNECTIONS:-50}"
REQUESTS="${REQUESTS:-0}"

if [[ ! -x "$CRYLOAD" ]]; then
  echo "cryload binary not found at $CRYLOAD" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f /tmp/cryload-bench-port
}
trap cleanup EXIT

rm -f /tmp/cryload-bench-port
ASDF_CRYSTAL_VERSION="${ASDF_CRYSTAL_VERSION:-1.19.1}" crystal run "$ROOT/scripts/bench_server.cr" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do
  if [[ -f /tmp/cryload-bench-port ]]; then
    break
  fi
  sleep 0.1
done
if [[ ! -f /tmp/cryload-bench-port ]]; then
  echo "bench server failed to start" >&2
  exit 1
fi
PORT="$(cat /tmp/cryload-bench-port)"
URL="http://127.0.0.1:${PORT}"

parse_cryload_json() {
  python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["summary"]
l = d["latency_ms"]
print(f"reqs={s['requests']} rps={s['requests_per_second']:.0f} p50={l['p50']:.2f}ms p99={l['p99']:.2f}ms")
PY
}

parse_hey() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
rps = 0.0
requests = 0
p50 = p99 = 0.0
for line in text.splitlines():
    if "Requests/sec:" in line:
        rps = float(line.split(":", 1)[1].strip())
    m = re.search(r"\[200\]\s+(\d+)\s+responses", line)
    if m:
        requests = int(m.group(1))
    if line.strip().startswith("50%"):
        p50 = float(line.split()[-2]) * 1000
    if line.strip().startswith("99%"):
        p99 = float(line.split()[-2]) * 1000
print(f"reqs={requests} rps={rps:.0f} p50={p50:.2f}ms p99={p99:.2f}ms")
PY
}

parse_wrk() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
requests = 0
rps = 0.0
p50 = p99 = 0.0
for line in text.splitlines():
    m = re.search(r"(\d+)\s+requests in", line)
    if m:
        requests = int(m.group(1))
    if "Requests/sec:" in line:
        rps = float(line.split(":", 1)[1].strip())
    if re.search(r"\b50%\s+", line):
        val = line.split()[-1]
        p50 = float(val.replace("ms", "")) if val.endswith("ms") else float(val.replace("us", "")) / 1000
    if re.search(r"\b99%\s+", line):
        val = line.split()[-1]
        p99 = float(val.replace("ms", "")) if val.endswith("ms") else float(val.replace("us", "")) / 1000
print(f"reqs={requests} rps={rps:.0f} p50={p50:.2f}ms p99={p99:.2f}ms")
PY
}

run_case() {
  local label="$1"
  shift
  local -a args=("$@")
  local out
  out="$(mktemp)"

  echo "=== ${label} ==="

  echo -n "  cryload: "
  "$CRYLOAD" "$URL" -d "$DURATION" -c "$CONNECTIONS" --no-progress --json >"$out" 2>/dev/null
  parse_cryload_json "$out"

  echo -n "  hey:     "
  "$HEY" -z "${DURATION}s" -c "$CONNECTIONS" "$URL" >"$out" 2>/dev/null
  parse_hey "$out"

  echo -n "  wrk:     "
  "$WRK" -t"$CONNECTIONS" -c"$CONNECTIONS" -d"${DURATION}s" --latency "$URL" >"$out" 2>/dev/null
  parse_wrk "$out"

  rm -f "$out"
  echo
}

echo "Benchmark target: $URL"
echo "Duration: ${DURATION}s  Connections: ${CONNECTIONS}"
echo

run_case "duration mode (${DURATION}s, c=${CONNECTIONS})"

CONNECTIONS=10 run_case "duration mode (${DURATION}s, c=10)" 
CONNECTIONS=100 run_case "duration mode (${DURATION}s, c=100)"

CONNECTIONS="${CONNECTIONS:-50}"
REQUESTS=$((DURATION * 15000))
echo "=== request-count mode (-n ${REQUESTS}, c=50) ==="
out="$(mktemp)"
echo -n "  cryload: "
"$CRYLOAD" "$URL" -n "$REQUESTS" -c 50 --no-progress --json >"$out" 2>/dev/null
parse_cryload_json "$out"
echo -n "  hey:     "
"$HEY" -n "$REQUESTS" -c 50 "$URL" >"$out" 2>/dev/null
parse_hey "$out"
echo -n "  wrk:     "
"$WRK" -t50 -c50 -n"$REQUESTS" --latency "$URL" >"$out" 2>/dev/null
parse_wrk "$out"
rm -f "$out"
echo
