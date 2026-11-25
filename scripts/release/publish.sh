#!/usr/bin/env bash
# F7.6: the GitHub release vX.Y.Z with Smalti.dmg and the notes of docs/releases/vX.Y.Z.md (the web reads them for
# /changelog). Prereleases never get here (build.sh refuses them).   publish.sh <vX.Y.Z> <Smalti.dmg>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
tag="${1:?tag}"; dmg="${2:?dmg}"
version="$(version_of_tag "$tag")" || exit 1
root="$(cd "$(dirname "$0")/../.." && pwd)"
notes="$root/docs/releases/$tag.md"
[[ -s "$notes" ]] || die "no release notes at docs/releases/$tag.md"
[[ "$(basename "$dmg")" == "$DMG_NAME" ]] || die "the asset must be named $DMG_NAME"
gh release create "$tag" "$dmg" --repo "$RELEASE_REPO" --title "Smalti $version" --notes-file "$notes" --verify-tag
