#!/usr/bin/env bash
# F2 (issue #6): Debug builds "Smalti Dev" (dev.simonriv.smalti.dev) so tests never touch the daily Release Smalti.
# Builds both configurations into build/ and reads their Info.plist. Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
products="$root/build/Build/Products"
total=27; n=0; failures=0
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
  if [[ "$got" =~ ^[0-9a-f]{7,}(-dirty)?$ ]]; then echo "[$n/$total] ok $name"
  else echo "[$n/$total] FAIL $name (got $got, want a short commit)"; failures=$((failures + 1)); fi
}

expect debug_bundle_id "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti.dev
expect debug_bundle_name "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleName "Smalti Dev"
expect debug_display_name "$products/Debug/Smalti Dev.app/Contents/Info.plist" CFBundleDisplayName "Smalti Dev"
expect release_bundle_id "$products/Release/Smalti.app/Contents/Info.plist" CFBundleIdentifier dev.simonriv.smalti
expect release_bundle_name "$products/Release/Smalti.app/Contents/Info.plist" CFBundleName Smalti
expect release_display_name "$products/Release/Smalti.app/Contents/Info.plist" CFBundleDisplayName Smalti
# F7.6: the version comes from the project, and the build number follows MAJOR*10000 + MINOR*100 + PATCH.
source "$root/scripts/release/lib.sh"
version="$(project_version)"
debug="$products/Debug/Smalti Dev.app"
release="$products/Release/Smalti.app"
expect debug_version "$debug/Contents/Info.plist" CFBundleShortVersionString "$version"
expect release_version "$release/Contents/Info.plist" CFBundleShortVersionString "$version"
expect release_build_number "$release/Contents/Info.plist" CFBundleVersion "$(build_number "$version")"
expect release_minimum_macos "$release/Contents/Info.plist" LSMinimumSystemVersion 27.0
commit debug_commit "$debug/Contents/Info.plist"
commit release_commit "$release/Contents/Info.plist"

# F7.6: Sparkle. Release checks smalti.sh; Smalti Dev has no feed (it never updates itself); both carry the public
# EdDSA key and send no system profile.
expect release_feed "$release/Contents/Info.plist" SUFeedURL https://smalti.sh/appcast.xml
expect debug_feed_is_empty "$debug/Contents/Info.plist" SUFeedURL ""
expect release_public_key "$release/Contents/Info.plist" SUPublicEDKey eR1CKdUMDqYUEtFiDOhLTDaXzkMEsyMekDhy/8QNZuQ=
expect release_no_system_profiling "$release/Contents/Info.plist" SUEnableSystemProfiling false
expect release_checks_automatically "$release/Contents/Info.plist" SUEnableAutomaticChecks true
expect release_never_installs_silently "$release/Contents/Info.plist" SUAutomaticallyUpdate false

check() { # case command…
  local name="$1"; shift
  n=$((n + 1))
  if "$@" > /dev/null 2>&1; then echo "[$n/$total] ok $name"
  else echo "[$n/$total] FAIL $name"; failures=$((failures + 1)); fi
}
arm64_only() { [[ "$(lipo -archs "$1")" == arm64 ]]; }
check release_is_arm64_only arm64_only "$release/Contents/MacOS/Smalti"
check debug_is_arm64_only arm64_only "$debug/Contents/MacOS/Smalti Dev"
check release_carries_the_notices "$root/scripts/release/check-notices.sh" --app "$release"

# F7.7: English is the development language and both localizations ship, so AppKit, Sparkle and the app agree on
# the interface's language (spike in the spec: with only `es`, panels stay Spanish on an English system).
expect debug_development_region "$debug/Contents/Info.plist" CFBundleDevelopmentRegion en
expect release_development_region "$release/Contents/Info.plist" CFBundleDevelopmentRegion en
localized() { [[ -s "$1/Contents/Resources/$2.lproj/Localizable.strings" ]]; }
check debug_ships_english localized "$debug" en
check debug_ships_spanish localized "$debug" es
check release_ships_english localized "$release" en
check release_ships_spanish localized "$release" es
exit "$failures"
