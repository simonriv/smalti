#!/usr/bin/env bash
# Builds GhosttyKit.xcframework and its runtime resources from the pinned vendor/ghostty commit.
set -euo pipefail
root="${SMALTI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
zig="${ZIG:-zig}"
ghostty="$root/vendor/ghostty"
out="$root/Packages/GhosttyAdapter/Frameworks"

required="$(sed -n 's/.*\.minimum_zig_version *= *"\([^"]*\)".*/\1/p' "$ghostty/build.zig.zon")"
found="$("$zig" version)"
# The same Zig line as the minimum (F7.6): at least that version, and no newer minor, so CI and local agree.
line="${required%.*}"
lowest="$(printf '%s\n%s\n' "$required" "$found" | sort -V)"  # not piped into head: SIGPIPE under pipefail
if [[ "${lowest%%$'\n'*}" != "$required" || "${found%.*}" != "$line" ]]; then
  echo "vendor/ghostty requires Zig $line.x (found $found)" >&2
  exit 1
fi

(cd "$ghostty" && "$zig" build -Doptimize=ReleaseFast -Demit-xcframework=true -Dxcframework-target=native -Demit-macos-app=false)

rm -rf "$out"
mkdir -p "$out/ghostty-resources"
cp -R "$ghostty/macos/GhosttyKit.xcframework" "$out/"
cp -R "$ghostty/zig-out/share/ghostty" "$out/ghostty-resources/ghostty"
cp -R "$ghostty/zig-out/share/terminfo" "$out/ghostty-resources/terminfo"
git -C "$ghostty" rev-parse HEAD > "$out/GhosttyKit.sha"
echo "GhosttyKit built from $(cat "$out/GhosttyKit.sha") into $out"
