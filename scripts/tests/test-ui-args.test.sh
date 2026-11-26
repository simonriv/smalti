#!/usr/bin/env bash
# The e2e suite never runs whole (testing rules): scripts/test-ui.sh without classes refuses before building.
# A fake xcodebuild on PATH records whether it was called. Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '#!/bin/sh\necho called >> "%s/calls"\nexit 1\n' "$work" > "$work/xcodebuild"; chmod +x "$work/xcodebuild"
total=2; failures=0
PATH="$work:$PATH" "$root/scripts/test-ui.sh" > "$work/out" 2>&1; status=$?
if [[ $status == 2 && ! -f "$work/calls" ]] && grep -q "name the affected" "$work/out"; then echo "[1/$total] ok refuses_without_classes"
else echo "[1/$total] FAIL refuses_without_classes (exit $status)"; sed 's/^/    /' "$work/out"; failures=$((failures + 1)); fi
PATH="$work:$PATH" "$root/scripts/test-ui.sh" WelcomeTests > /dev/null 2>&1
if [[ -f "$work/calls" ]]; then echo "[2/$total] ok builds_when_classes_are_named"
else echo "[2/$total] FAIL builds_when_classes_are_named"; failures=$((failures + 1)); fi
exit "$failures"
