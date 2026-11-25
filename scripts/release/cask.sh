#!/usr/bin/env bash
# F7.6: Casks/smalti.rb for the tap, on stdout.   cask.sh <version> <sha256 of Smalti.dmg>
# Never run `brew uninstall --zap` with this cask on a machine whose Smalti state matters: zap deletes it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
version="${1:?version}"; sha="${2:?sha256}"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "sha256 must be 64 hex characters"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" "$(dirname "$0")/templates/smalti.rb.tmpl"
