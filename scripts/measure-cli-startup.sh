#!/usr/bin/env bash
# F5.5 C9: start-up time of `smalti event Stop` (the path every Claude Code hook takes), with a socket that does not
# exist so it exits at once. Builds the CLI in release unless binaries are given, then runs each one `runs` times with
# a clean environment (`env -i`, `SMALTI_SOCKET` and `SMALTI_PANE_ID` pointing nowhere) and stdin from /dev/null, and
# prints the p50 and the nearest-rank p95 in ms. Usage:
#   scripts/measure-cli-startup.sh [runs] [binary…]   (default: 50 runs of the freshly built smalti)
# Prints `[k/n] ok <binary> p50 <ms> ms p95 <ms> ms` per binary, or `[k/n] FAIL <binary> <why>` and goes on; exits 1
# if any failed.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-50}"
shift || true
binaries=("$@")
if (( ${#binaries[@]} == 0 )); then
  swift build -c release --package-path "$root/Packages/IPCAdapter" --product smalti > /dev/null || exit 1
  binaries=("$(swift build -c release --package-path "$root/Packages/IPCAdapter" --show-bin-path)/smalti")
fi

total=${#binaries[@]}
index=0
failures=0
for binary in "${binaries[@]}"; do
  index=$((index + 1))
  if result="$(python3 -I - "$binary" "$runs" 2>&1 <<'EOF'
import math, statistics, subprocess, sys, time
binary, runs = sys.argv[1], int(sys.argv[2])
command = ["/usr/bin/env", "-i", "SMALTI_SOCKET=/nonexistent/smalti.sock", "SMALTI_PANE_ID=none", binary, "event", "Stop"]
samples = []
for _ in range(runs + 3):
    start = time.perf_counter_ns()
    subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    samples.append((time.perf_counter_ns() - start) / 1e6)
samples = sorted(samples[3:])  # the first runs warm the disk cache
p95 = samples[math.ceil(len(samples) * 0.95) - 1]  # nearest rank
print(f"p50 {statistics.median(samples):.2f} ms p95 {p95:.2f} ms")
EOF
)"; then
    echo "[$index/$total] ok $binary $result"
  else
    echo "[$index/$total] FAIL $binary $(echo "$result" | tail -1)"
    failures=$((failures + 1))
  fi
done
(( failures == 0 ))
