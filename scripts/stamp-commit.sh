#!/usr/bin/env bash
# F4.5: writes the short commit of the build into the app's Info.plist as SmaltiGitCommit ("Acerca de Smalti").
# Runs as an Xcode build phase that lists the Info.plist as its input, so it runs after the plist is processed, and
# before code signing.
set -euo pipefail
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
commit="$(git -C "$SRCROOT/.." rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
# A build with uncommitted changes says so, so a report never passes it off as that commit.
if [[ "$commit" != unknown ]] && ! git -C "$SRCROOT/.." diff --quiet HEAD -- 2>/dev/null; then commit="$commit-dirty"; fi
/usr/libexec/PlistBuddy -c "Set :SmaltiGitCommit $commit" "$plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SmaltiGitCommit string $commit" "$plist"
