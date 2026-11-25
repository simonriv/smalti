#!/usr/bin/env bash
# F7.6: the Release Smalti.app for a tag, checked before anything is published.   build.sh <vX.Y.Z> <out dir>
# Test builds (install/update scripts) override, by environment: SMALTI_VERSION (version and build number),
# SMALTI_BUNDLE_ID, SMALTI_FEED_URL and SMALTI_ED_PUBLIC_KEY. A real release sets none of them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
tag="${1:?tag}"; out="${2:?out dir}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(version_of_tag "$tag")" || exit 1
expected="${SMALTI_VERSION:-$(project_version)}"
[[ "$version" == "$expected" ]] || die "tag $tag does not match MARKETING_VERSION $expected"

settings=(ARCHS=arm64 ONLY_ACTIVE_ARCH=NO)
[[ -n "${SMALTI_VERSION:-}" ]] && settings+=(MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$(build_number "$version")")
[[ -n "${SMALTI_BUNDLE_ID:-}" ]] && settings+=(PRODUCT_BUNDLE_IDENTIFIER="$SMALTI_BUNDLE_ID")
[[ -n "${SMALTI_FEED_URL:-}" ]] && settings+=(SMALTI_FEED_URL="$SMALTI_FEED_URL")
[[ -n "${SMALTI_ED_PUBLIC_KEY:-}" ]] && settings+=(SMALTI_ED_PUBLIC_KEY="$SMALTI_ED_PUBLIC_KEY")

mkdir -p "$out"
xcodebuild -version | head -1
xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Release \
  -derivedDataPath "$out/dd" "${settings[@]}" build > "$out/xcodebuild.log" 2>&1 \
  || { tail -30 "$out/xcodebuild.log"; die "xcodebuild failed (see $out/xcodebuild.log)"; }
app="$out/dd/Build/Products/Release/Smalti.app"
plist="$app/Contents/Info.plist"
value() { plutil -extract "$1" raw "$plist" 2>/dev/null || echo "<missing>"; }

[[ "$(lipo -archs "$app/Contents/MacOS/Smalti")" == arm64 ]] || die "the binary is not arm64 only"
codesign --verify --deep --strict "$app" || die "the signature does not verify"
signature="$(codesign -dv "$app" 2>&1)"  # captured first: grep -q under pipefail would SIGPIPE codesign
[[ "$signature" == *"Signature=adhoc"* ]] || die "the app is not signed ad hoc"
[[ "$(value CFBundleShortVersionString)" == "$version" ]] || die "CFBundleShortVersionString is not $version"
[[ "$(value CFBundleVersion)" == "$(build_number "$version")" ]] || die "CFBundleVersion is not $(build_number "$version")"
[[ "$(value LSMinimumSystemVersion)" == "$MINIMUM_SYSTEM_VERSION" ]] || die "LSMinimumSystemVersion is not $MINIMUM_SYSTEM_VERSION"
[[ "$(value SUFeedURL)" == http* ]] || die "SUFeedURL is missing"
[[ "$(value SUPublicEDKey)" != "<missing>" && -n "$(value SUPublicEDKey)" ]] || die "SUPublicEDKey is missing"
[[ "$(value SUEnableSystemProfiling)" == false ]] || die "SUEnableSystemProfiling must be NO"
"$root/scripts/release/check-notices.sh" --app "$app" > /dev/null || die "THIRD_PARTY_NOTICES.md is incomplete in the bundle"

rm -rf "$out/Smalti.app" && ditto "$app" "$out/Smalti.app"
echo "$out/Smalti.app"
