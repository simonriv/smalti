#!/usr/bin/env bash
# Fails the build when GhosttyKit.xcframework was not built from the pinned vendor/ghostty commit.
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
sha_file="$root/Packages/GhosttyAdapter/Frameworks/GhosttyKit.sha"
pinned="$(git -C "$root/vendor/ghostty" rev-parse HEAD)"

if [[ ! -f "$sha_file" ]]; then
  echo "GhosttyKit.xcframework is missing (no $sha_file). Run scripts/build-ghostty.sh" >&2
  exit 1
fi
built="$(tr -d '[:space:]' < "$sha_file")"
if [[ "$built" != "$pinned" ]]; then
  echo "GhosttyKit.xcframework was built from $built but vendor/ghostty is at $pinned. Run scripts/build-ghostty.sh" >&2
  exit 1
fi
