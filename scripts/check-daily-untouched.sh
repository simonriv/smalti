#!/usr/bin/env bash
# F2 C1 (issue #6): runs a command (e.g. the UI suite) and fails if it disturbed the daily Smalti: the Release
# instance must keep its PID and its state file must not change. Usage: scripts/check-daily-untouched.sh <command…>
set -uo pipefail
state="$HOME/Library/Application Support/Smalti/session.json"
pid="$(pgrep -x Smalti | head -1)"
[[ -n "$pid" ]] || { echo "open the daily Smalti (Release) first"; exit 2; }
stamp() { [[ -f "$state" ]] && stat -f %m "$state" || echo absent; }
before="$(stamp)"

"$@"; status=$?

failures=0
if kill -0 "$pid" 2>/dev/null; then echo "ok daily Smalti still running (pid $pid)"
else echo "FAIL daily Smalti (pid $pid) was closed"; failures=1; fi
if [[ "$(stamp)" == "$before" ]]; then echo "ok daily state untouched ($before)"
else echo "FAIL daily state changed ($before → $(stamp))"; failures=1; fi
(( failures == 0 )) || exit 1
exit "$status"
