#!/usr/bin/env bash
# F7.6: pushes release/<tag> to smalti-web with the new <item> prepended to public/appcast.xml.
#   [DEPLOY_KEY=…] push-appcast.sh <git url> <vX.Y.Z> <item.xml>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
url="${1:?url}"; tag="${2:?tag}"; item="${3:?item}"
version="$(version_of_tag "$tag")" || exit 1
grep -q "<title>$version</title>" "$item" || die "the item is not version $version"
grep -q 'sparkle:edSignature="[^"]' "$item" || die "the item has no sparkle:edSignature"
dir="$(mktemp -d "${TMPDIR:-/tmp}/satellite.XXXXXX")"; trap 'rm -rf "$dir"' EXIT
clone_satellite "$url" "$dir"
python3 - "$dir/repo/public/appcast.xml" "$item" <<'P'
import sys
path, item = sys.argv[1], open(sys.argv[2]).read().rstrip("\n") + "\n"
text = open(path).read()
marker = "prepends one <item> per version"
lines = text.splitlines(keepends=True)
at = next((i + 1 for i, l in enumerate(lines) if marker in l), None)
if at is None:
    at = next((i for i, l in enumerate(lines) if "<item>" in l or "</channel>" in l), None)
if at is None:
    sys.exit("no <channel> in appcast.xml")
open(path, "w").write("".join(lines[:at]) + item + "".join(lines[at:]))
P
push_branch "$dir/repo" "release/$tag" "chore(appcast): Smalti $version"
echo "release/$tag"
