#!/usr/bin/env bash
# F2 (issue #6): Debug builds "Smalti Dev" (dev.simonriv.smalti.dev) so tests never touch the daily Release Smalti.
# Builds both configurations into build/ and reads their Info.plist. Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
products="$root/build/Build/Products"
total=4; n=0; failures=0

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

expect debug_bundle_id "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti.dev
expect debug_display_name "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleDisplayName "Smalti Dev"
expect release_bundle_id "$products/Release/Smalti.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti
expect release_display_name "$products/Release/Smalti.app/Contents/Info.plist" CFBundleDisplayName Smalti
exit "$failures"
