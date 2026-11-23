#!/usr/bin/env bash
# F3 C10: runs the indexing benchmark N times (default 5) against the user's real ~/.claude, read-only, each run
# from an empty temporary index, in a release build. Prints one "[n/total] ok …" line per run with its figures.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"
status=0
for run in $(seq 1 "$runs"); do
  line="$(SMALTI_BENCH=1 swift test --package-path "$root/Packages/ClaudeTelemetryAdapter" -c release \
    --filter todayFromAnEmptyIndexAndAnUnchangedRefresh 2>&1 | grep '^BENCH' | tr '\n' ' ')"
  if [[ -n "$line" ]]; then echo "[$run/$runs] ok ${line#BENCH }"; else echo "[$run/$runs] FAIL no result"; status=1; fi
done
exit "$status"
