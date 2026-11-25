#!/usr/bin/env bash
# F7.6: EdDSA signature of an update, as "<signature> <length>". The private key comes on stdin and never touches a
# file or the log; the signature is verified with the same key before it is printed.
#   printf '%s' "$KEY" | SPARKLE_BIN=<Sparkle bin dir> sign-update.sh <Smalti.dmg>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
file="${1:?file}"; bin="${SPARKLE_BIN:?SPARKLE_BIN must point at the bin directory of Sparkle}"
key="$(cat)"; [[ -n "$key" ]] || die "no key on stdin"
signature="$(printf '%s' "$key" | "$bin/sign_update" --ed-key-file - -p "$file")"
printf '%s' "$key" | "$bin/sign_update" --verify --ed-key-file - "$file" "$signature" > /dev/null \
  || die "the signature does not verify"
echo "$signature $(stat -f %z "$file")"
