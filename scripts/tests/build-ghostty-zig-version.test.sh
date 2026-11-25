#!/usr/bin/env bash
# build-ghostty.sh must refuse a Zig older than vendor/ghostty's minimum_zig_version.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/build-ghostty.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

mkdir -p "$work/vendor/ghostty"
printf '.{\n    .minimum_zig_version = "0.17.0",\n}\n' > "$work/vendor/ghostty/build.zig.zon"
printf '#!/bin/sh\necho 0.16.0\n' > "$work/fake-zig"; chmod +x "$work/fake-zig"

set +e; err="$(SMALTI_ROOT="$work" ZIG="$work/fake-zig" "$SCRIPT" 2>&1 >/dev/null)"; got=$?; set -e
status=0
if [[ "$got" == 1 && "$err" == *"requires Zig 0.17.x (found 0.16.0)"* ]]; then echo "ok old_zig_is_rejected"
else echo "FAIL old_zig_is_rejected (exit $got, stderr: $err)"; status=1; fi

# F7.6 final review (M4): a newer minor (0.18) is refused too, so CI and local builds use the same Zig line.
printf '#!/bin/sh\necho 0.18.0\n' > "$work/fake-zig"
set +e; err="$(SMALTI_ROOT="$work" ZIG="$work/fake-zig" "$SCRIPT" 2>&1 >/dev/null)"; got=$?; set -e
if [[ "$got" == 1 && "$err" == *"requires Zig 0.17.x (found 0.18.0)"* ]]; then echo "ok newer_minor_is_rejected"
else echo "FAIL newer_minor_is_rejected (exit $got, stderr: $err)"; status=1; fi
exit $status
