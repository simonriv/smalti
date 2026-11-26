#!/usr/bin/env bash
# F9 C5, C7, C8: over a Claude home (by default the user's ~/.claude, read only), N runs (default 5) of the search
# over a project (first result and whole), the read of a session with its rows, and the memory the open session adds.
#   scripts/measure-timeline.sh [runs] <projectRoot> <query> <sessionID> [claudeHome]
# Prints one "[n/total] ok …" line per run.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"; project="${2:?project root}"; query="${3:?query}"; session="${4:?session id}"
home="${5:-$HOME/.claude}"
swift build -c release --disable-keychain --package-path "$root/scripts/timeline-bench" > /dev/null 2>&1 \
  || { swift build -c release --disable-keychain --package-path "$root/scripts/timeline-bench" 2>&1 | tail -20; exit 1; }
bin="$(swift build -c release --disable-keychain --package-path "$root/scripts/timeline-bench" --show-bin-path)/TimelineBench"
status=0
for run in $(seq 1 "$runs"); do
  line="$("$bin" "$home" "$project" "$query" "$session" 2>&1 | grep '^BENCH')"
  if [[ -n "$line" ]]; then echo "[$run/$runs] ok ${line#BENCH }"; else echo "[$run/$runs] FAIL no result"; status=1; fi
done
exit "$status"
