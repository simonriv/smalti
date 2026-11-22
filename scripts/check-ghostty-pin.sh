#!/usr/bin/env bash
# Fails the build unless GhosttyKit.xcframework was built from the pinned Ghostty commit. The pin is the
# superproject's gitlink for vendor/ghostty (index, so a staged bump counts); the checkout must match it and
# be clean.
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
sha_file="$root/Packages/GhosttyAdapter/Frameworks/GhosttyKit.sha"
pinned="$(git -C "$root" ls-files -s vendor/ghostty | awk '{ print $2 }')"
checkout="$(git -C "$root/vendor/ghostty" rev-parse HEAD)"

if [[ -z "$pinned" ]]; then
  echo "vendor/ghostty is not a submodule of $root" >&2
  exit 1
fi
if [[ "$checkout" != "$pinned" ]]; then
  echo "vendor/ghostty is checked out at $checkout but the superproject pins $pinned. Run git submodule update" >&2
  exit 1
fi
if [[ -n "$(git -C "$root/vendor/ghostty" status --porcelain)" ]]; then
  echo "vendor/ghostty has local changes; the build must come from the pinned commit as is" >&2
  exit 1
fi
if [[ ! -f "$sha_file" ]]; then
  echo "GhosttyKit.xcframework is missing (no $sha_file). Run scripts/build-ghostty.sh" >&2
  exit 1
fi
built="$(tr -d '[:space:]' < "$sha_file")"
if [[ "$built" != "$pinned" ]]; then
  echo "GhosttyKit.xcframework was built from $built but vendor/ghostty is at $pinned. Run scripts/build-ghostty.sh" >&2
  exit 1
fi
