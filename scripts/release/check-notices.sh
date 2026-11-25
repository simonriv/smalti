#!/usr/bin/env bash
# F7.6: fails unless THIRD_PARTY_NOTICES.md has a table row and a section for every component Smalti ships.
#   check-notices.sh <notices.md> [<binary>]   the repo's file, and the components found in <binary>
#   check-notices.sh --app <Smalti.app>        the copy inside the bundle, against the app's own binary
# Components the binary may or may not link are found by a symbol of theirs (`nm`); the rest are always required.
set -uo pipefail

if [[ "${1:-}" == "--app" ]]; then
  app="${2:?usage: check-notices.sh --app <Smalti.app>}"
  notices="$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
  binary="$app/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
else
  notices="${1:?usage: check-notices.sh <notices.md> [<binary>]}"
  binary="${2:-}"
fi

always=(
  "libghostty" "Sparkle" "TOMLDecoder" "Fig autocomplete specs" "Inter" "JetBrains Mono" "Symbols Nerd Font"
  "Zig standard library and compiler-rt" "libxev" "z2d" "uucode" "zig-objc"
)
# symbol (extended regex on `nm` output) | component
probes=(
  "_sentry_init$|sentry-native"
  "sentry__breakpad|Breakpad"
  "google_breakpad|Breakpad"
  "ImGui|Dear ImGui"
  "_ImGui_|Dear Bindings"
  "glslang|glslang"
  "_onig_new|Oniguruma"
  "simdutf|simdutf"
  "hwy|Highway"
  "_wuffs_|Wuffs"
  "_png_create_read_struct|libpng"
  " _inflate$|zlib"
  "_spvc_|SPIRV-Cross"
  "_FT_Init_FreeType|FreeType"
  "_libintl_|GNU libintl (gettext-runtime)"
)

[[ -f "$notices" ]] || { echo "missing $notices"; exit 1; }

required=("${always[@]}")
if [[ -n "$binary" ]]; then
  symbols="$(nm "$binary" 2>/dev/null)" || { echo "cannot read symbols of $binary"; exit 1; }
  for probe in "${probes[@]}"; do
    grep -qE "${probe%%|*}" <<< "$symbols" && required+=("${probe#*|}")
  done
fi

missing=()
for component in "${required[@]}"; do
  grep -qxF "## $component" "$notices" && grep -qF "| $component |" "$notices" || missing+=("$component")
done
if (( ${#missing[@]} > 0 )); then
  printf 'THIRD_PARTY_NOTICES.md lacks: %s\n' "${missing[@]}"
  exit 1
fi
echo "notices cover ${#required[@]} components"
