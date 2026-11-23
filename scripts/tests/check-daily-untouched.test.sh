#!/usr/bin/env bash
# Tests for scripts/check-daily-untouched.sh with a fake daily instance (a sleep) and a throwaway state directory.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-daily-untouched.sh"
work="$(mktemp -d)"
# Not our child: a killed child stays a zombie that `kill -0` still finds until we reap it.
daily="$(sh -c 'sleep 300 > /dev/null 2>&1 & echo $!')"
trap 'kill "$daily" 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$work/state/observatory" "$work/state/scrollback" "$work/state/history"; echo conf > "$work/state/ghostty.conf"
export SMALTI_DAILY_STATE_DIR="$work/state" SMALTI_DAILY_PID="$daily"
total=9; n=0; failures=0

expect() { # name expected_exit command...
  local name="$1" want="$2" got; shift 2
  n=$((n + 1))
  "$SCRIPT" "$@" > /dev/null 2>&1; got=$?
  if [[ "$got" == "$want" ]]; then echo "[$n/$total] ok $name"
  else echo "[$n/$total] FAIL $name (exit $got, want $want)"; failures=$((failures + 1)); fi
}

expect untouched_passes 0 true
expect command_status_is_kept 3 sh -c 'exit 3'
expect any_changed_file_fails 1 sh -c "sleep 1; echo new > '$work/state/ghostty.conf'"
expect missing_command_is_usage 2
# The daily Smalti rewrites these on its own (observatory refresh, autosave, its panes' history): not a disturbance.
expect own_observatory_and_session_writes_pass 0 sh -c "sleep 1; echo i > '$work/state/observatory/index.json'; echo s > '$work/state/session.json'"
expect own_scrollback_and_history_writes_pass 0 sh -c "sleep 1; echo b > '$work/state/scrollback/p.lzfse'; echo h > '$work/state/history/p.zsh_history'"
expect a_new_unexpected_file_still_fails 1 sh -c "echo x > '$work/state/other.json'"
n=$((n + 1))
named="$("$SCRIPT" sh -c "sleep 1; echo other > '$work/state/ghostty.conf'" 2>&1)"
if [[ "$named" == *"changed: ghostty.conf"* ]]; then echo "[$n/$total] ok changed_file_is_named"
else echo "[$n/$total] FAIL changed_file_is_named"; failures=$((failures + 1)); fi
expect closed_daily_fails 1 kill "$daily"
exit "$failures"
