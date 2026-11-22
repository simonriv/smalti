#!/usr/bin/env bash
# Tests for scripts/check-ghostty-pin.sh against a throwaway fake repo.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-ghostty-pin.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

mkdir -p "$work/vendor/ghostty" "$work/Packages/GhosttyAdapter/Frameworks"
git -C "$work/vendor/ghostty" init -q
git -C "$work/vendor/ghostty" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
head_sha="$(git -C "$work/vendor/ghostty" rev-parse HEAD)"
sha_file="$work/Packages/GhosttyAdapter/Frameworks/GhosttyKit.sha"
failures=0

expect() { # name expected_exit stderr_substring
  local name="$1" want="$2" needle="$3" got err
  set +e; err="$("$SCRIPT" "$work" 2>&1 >/dev/null)"; got=$?; set -e
  if [[ "$got" == "$want" && "$err" == *"$needle"* ]]; then echo "ok $name"
  else echo "FAIL $name (exit $got, stderr: $err)"; failures=$((failures + 1)); fi
}

echo "$head_sha" > "$sha_file";       expect matching_sha_passes 0 ""
echo "0000000000" > "$sha_file";      expect mismatched_sha_fails 1 "was built from 0000000000"
rm "$sha_file";                       expect missing_sha_fails 1 "Run scripts/build-ghostty.sh"
exit "$failures"
