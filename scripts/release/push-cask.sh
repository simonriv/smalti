#!/usr/bin/env bash
# F7.6: pushes release/<tag> to the tap with Casks/smalti.rb.   [DEPLOY_KEY=…] push-cask.sh <git url> <vX.Y.Z> <smalti.rb>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
url="${1:?url}"; tag="${2:?tag}"; cask="${3:?cask}"
version="$(version_of_tag "$tag")" || exit 1
grep -q "^  version \"$version\"$" "$cask" || die "the cask is not version $version"
dir="$(clone_satellite "$url")"; trap 'rm -rf "$dir" "$dir.key"' EXIT
mkdir -p "$dir/repo/Casks" && cp "$cask" "$dir/repo/Casks/smalti.rb"
push_branch "$dir/repo" "release/$tag" "smalti $version"
echo "release/$tag"
