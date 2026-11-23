#!/usr/bin/env bash
# F2 (issue #6): Debug builds "Smalti Dev" (dev.simonriv.smalti.dev) so tests never touch the daily Release Smalti.
# Builds both configurations into build/ and reads their Info.plist. Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
products="$root/build/Build/Products"
total=10; n=0; failures=0
mkdir -p "$root/build"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The Release copy built here shares the daily bundle ID; keep LaunchServices pointing at /Applications.
trap '"$lsregister" -u "$products/Release/Smalti.app" 2>/dev/null' EXIT

for configuration in Debug Release; do
  xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration "$configuration" \
    -derivedDataPath "$root/build" build > "$root/build/identity-$configuration.log" 2>&1 \
    || { echo "build $configuration failed (see build/identity-$configuration.log)"; exit 1; }
done

expect() { # case plist key expected
  local name="$1" plist="$2" key="$3" want="$4" got
  n=$((n + 1))
  got="$(plutil -extract "$key" raw "$plist" 2>/dev/null || echo "<missing>")"
  if [[ "$got" == "$want" ]]; then echo "[$n/$total] ok $name"
  else echo "[$n/$total] FAIL $name (got $got, want $want)"; failures=$((failures + 1)); fi
}

# F4.5: "Acerca de Smalti" shows the version and the commit the build came from.
commit() { # case plist
  local name="$1" plist="$2" got
  n=$((n + 1))
  got="$(plutil -extract SmaltiGitCommit raw "$plist" 2>/dev/null || echo "<missing>")"
  if [[ "$got" =~ ^[0-9a-f]{7,}$ ]]; then echo "[$n/$total] ok $name"
  else echo "[$n/$total] FAIL $name (got $got, want a short commit)"; failures=$((failures + 1)); fi
}

expect debug_bundle_id "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti.dev
expect debug_bundle_name "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleName "Smalti Dev"
expect debug_display_name "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleDisplayName "Smalti Dev"
expect release_bundle_id "$products/Release/Smalti.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti
expect release_bundle_name "$products/Release/Smalti.app/Contents/Info.plist" CFBundleName Smalti
expect release_display_name "$products/Release/Smalti.app/Contents/Info.plist" CFBundleDisplayName Smalti
expect debug_version "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleShortVersionString 0.4.5
expect release_version "$products/Release/Smalti.app/Contents/Info.plist" CFBundleShortVersionString 0.4.5
commit debug_commit "$products/Debug/Smalti Dev.app/Contents/Info.plist"
commit release_commit "$products/Release/Smalti.app/Contents/Info.plist"
exit "$failures"
