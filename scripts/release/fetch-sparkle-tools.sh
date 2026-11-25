#!/usr/bin/env bash
# F7.6: Sparkle's command line tools (sign_update), from the release the app links, checked against its sha256.
#   fetch-sparkle-tools.sh <dir>   -> prints <dir>/bin
set -euo pipefail
source "$(dirname "$0")/lib.sh"
dir="${1:?dir}"
readonly version="2.10.1"
readonly sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
mkdir -p "$dir"
archive="$dir/Sparkle-$version.tar.xz"
curl -fsSL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
echo "$sha256  $archive" | shasum -a 256 -c - > /dev/null || die "Sparkle $version does not match its sha256"
tar -xf "$archive" -C "$dir" bin
echo "$dir/bin"
