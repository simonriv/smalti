#!/usr/bin/env bash
# F5.5 C9: start-up time of `smalti event Stop` (the path every Claude Code hook takes), without a socket so it exits
# at once. Builds the CLI in release unless binaries are given, then runs each one `runs` times with a clean
# environment and stdin from /dev/null, and prints the p50 and p95 in ms. Usage:
#   scripts/measure-cli-startup.sh [runs] [binary…]   (default: 50 runs of the freshly built smalti)
# Prints `[k/n] ok <binary> p50 <ms> ms p95 <ms> ms` per binary.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-50}"
shift || true
binaries=("$@")
if (( ${#binaries[@]} == 0 )); then
  swift build -c release --package-path "$root/Packages/IPCAdapter" --product smalti > /dev/null
  binaries=("$(swift build -c release --package-path "$root/Packages/IPCAdapter" --show-bin-path)/smalti")
fi

total=${#binaries[@]}
index=0
for binary in "${binaries[@]}"; do
  index=$((index + 1))
  result="$(python3 -I - "$binary" "$runs" <<'EOF'
import statistics, subprocess, sys, time
binary, runs = sys.argv[1], int(sys.argv[2])
samples = []
for _ in range(runs + 3):
    start = time.perf_counter_ns()
    subprocess.run([binary, "event", "Stop"], env={"HOME": "/tmp", "PATH": "/usr/bin:/bin"},
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    samples.append((time.perf_counter_ns() - start) / 1e6)
samples = sorted(samples[3:])  # the first runs warm the disk cache
print(f"p50 {statistics.median(samples):.2f} ms p95 {samples[int(len(samples) * 0.95) - 1]:.2f} ms")
EOF
)"
  echo "[$index/$total] ok $binary $result"
done
