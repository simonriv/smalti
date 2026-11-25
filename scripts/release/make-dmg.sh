#!/usr/bin/env bash
# F7.6: Smalti.dmg with the app and a link to /Applications, so the user drags it there (opening it from the DMG
# would leave Sparkle unable to update it).   make-dmg.sh <Smalti.app> <out.dmg>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
app="${1:?app}"; dmg="${2:?dmg}"
[[ -d "$app" ]] || die "no app at $app"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname Smalti -srcfolder "$stage" -fs APFS -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"
echo "$dmg"
