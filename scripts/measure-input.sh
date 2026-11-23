#!/usr/bin/env bash
# F4 C1: suggestion latency end to end (zsh sends `line` → Smalti answers → ghost text painted) with a 50,000-entry
# history, keystroke by keystroke, in a release build, N runs (default 5). `--real-history` uses the user's
# ~/.zsh_history read-only and only in memory. Prints one "[n/total] ok …" line per run.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"; shift || true
swift build -c release --package-path "$root/scripts/input-bench" > /dev/null 2>&1 \
  || { swift build -c release --package-path "$root/scripts/input-bench" 2>&1 | tail -20; exit 1; }
bin="$(swift build -c release --package-path "$root/scripts/input-bench" --show-bin-path)/InputBench"
status=0
for run in $(seq 1 "$runs"); do
  line="$("$bin" "$@" 2>&1 | grep '^BENCH')"
  if [[ -n "$line" ]]; then echo "[$run/$runs] ok ${line#BENCH }"; else echo "[$run/$runs] FAIL no result"; status=1; fi
done
exit "$status"
