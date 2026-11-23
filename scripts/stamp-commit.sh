#!/usr/bin/env bash
# F4.5: writes the short commit of the build into the app's Info.plist as SmaltiGitCommit ("Acerca de Smalti").
# Runs as an Xcode build phase, after Info.plist is processed and before code signing.
set -euo pipefail
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
commit="$(git -C "$SRCROOT/.." rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Set :SmaltiGitCommit $commit" "$plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SmaltiGitCommit string $commit" "$plist"
