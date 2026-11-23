#!/usr/bin/env bash
# F2 C1 (issue #6): runs a command (e.g. the UI suite) and fails if it disturbed the daily Smalti: the Release
# instance from /Applications must keep its PID, and no file of its state directory may appear, change or vanish,
# except the ones the running daily Smalti rewrites by itself: its observatory index (every refresh while Claude Code
# writes transcripts), its autosaved session and scrollback, and its own panes' history.
# Usage: scripts/check-daily-untouched.sh <command…>. Exits 2 on misuse, 1 if the daily Smalti was disturbed,
# otherwise with the command's own status. SMALTI_DAILY_STATE_DIR and SMALTI_DAILY_PID override the targets (tests).
set -uo pipefail
(( $# > 0 )) || { echo "usage: $0 <command…>"; exit 2; }
state="${SMALTI_DAILY_STATE_DIR:-$HOME/Library/Application Support/Smalti}"
pid="${SMALTI_DAILY_PID:-$(pgrep -f '^/Applications/Smalti.app/Contents/MacOS/Smalti' | head -1)}"
[[ -n "$pid" ]] || { echo "open the daily Smalti (/Applications/Smalti.app) first"; exit 2; }
listing() { # every file but the daily app's own periodic writes, with size and modification time, sorted
  [[ -d "$state" ]] || { echo absent; return; }
  (cd "$state" && find . -type f -exec stat -f '%N %z %m' {} + | sed 's|^\./||' \
    | grep -vE '^(observatory/index\.json|session\.json|scrollback/[^ ]+|history/[^ ]+) ' | sort)
}
before="$(listing)"

"$@"; status=$?

sleep 1  # a termination signal sent at the very end of the command takes a moment to land
failures=0
if kill -0 "$pid" 2>/dev/null; then echo "ok daily Smalti still running (pid $pid)"
else echo "FAIL daily Smalti (pid $pid) was closed"; failures=1; fi
after="$(listing)"
if [[ "$after" == "$before" ]]; then echo "ok daily state untouched"
else
  echo "FAIL daily state changed in $state"
  # Names each file that appeared, changed or vanished, so a change can be traced to whoever wrote it.
  diff <(echo "$before") <(echo "$after") | sed -nE 's/^[<>] (.*) [0-9]+ [0-9]+$/\1/p' | sort -u | sed 's/^/  changed: /'
  failures=1
fi
(( failures == 0 )) || exit 1
exit "$status"
