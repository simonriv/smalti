#!/usr/bin/env bash
# F7.6: sets MARKETING_VERSION and CURRENT_PROJECT_VERSION (MAJOR*10000 + MINOR*100 + PATCH) in every
# configuration of the project.   bump-version.sh X.Y.Z
set -euo pipefail
source "$(dirname "$0")/lib.sh"
version="${1:?version}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z: $version"
build="$(build_number "$version")" || exit 1
project="$(cd "$(dirname "$0")/../.." && pwd)/App/Smalti.xcodeproj/project.pbxproj"
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build;/" "$project"
echo "$version ($build)"
