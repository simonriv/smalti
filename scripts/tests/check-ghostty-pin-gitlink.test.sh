#!/usr/bin/env bash
# check-ghostty-pin.sh must compare against the superproject's gitlink (the real pin) and reject a dirty checkout.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-ghostty-pin.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

g init -q "$work"
g -C "$work" init -q vendor/ghostty
g -C "$work/vendor/ghostty" commit -q --allow-empty -m pinned
pinned="$(git -C "$work/vendor/ghostty" rev-parse HEAD)"
g -C "$work" add vendor/ghostty 2>/dev/null      # records the gitlink (the pin)
g -C "$work/vendor/ghostty" commit -q --allow-empty -m newer
newer="$(git -C "$work/vendor/ghostty" rev-parse HEAD)"
mkdir -p "$work/Packages/GhosttyAdapter/Frameworks"
sha_file="$work/Packages/GhosttyAdapter/Frameworks/GhosttyKit.sha"
failures=0

expect() { # name expected_exit stderr_substring
  local name="$1" want="$2" needle="$3" got err
  set +e; err="$("$SCRIPT" "$work" 2>&1 >/dev/null)"; got=$?; set -e
  if [[ "$got" == "$want" && "$err" == *"$needle"* ]]; then echo "ok $name"
  else echo "FAIL $name (exit $got, stderr: $err)"; failures=$((failures + 1)); fi
}

echo "$newer" > "$sha_file"
expect checkout_ahead_of_pin_fails 1 "superproject pins $pinned"

g -C "$work/vendor/ghostty" checkout -q "$pinned" 2>/dev/null
echo "$pinned" > "$sha_file"
expect matching_pin_passes 0 ""

touch "$work/vendor/ghostty/stray.txt"
expect dirty_checkout_fails 1 "has local changes"
exit "$failures"
