#!/usr/bin/env bash
# F7.6: EdDSA signature of an update, as "<signature> <length>". The private key comes on stdin and never touches a
# file or the log. Before signing, its public half must be <public key> (the app's SUPublicEDKey): a rotated or
# mistaken secret would otherwise publish an update no installed Smalti accepts.
#   printf '%s' "$KEY" | SPARKLE_BIN=<Sparkle bin dir> sign-update.sh <Smalti.dmg> <SUPublicEDKey>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
file="${1:?file}"; public="${2:?the app public key}"
bin="${SPARKLE_BIN:?SPARKLE_BIN must point at the bin directory of Sparkle}"
key="$(cat)"; [[ -n "$key" ]] || die "no key on stdin"
[[ "$(printf '%s' "$key" | "$(dirname "$0")/public-key.sh")" == "$public" ]] \
  || die "the signing key is not the one whose public half the app carries (SUPublicEDKey)"
signature="$(printf '%s' "$key" | "$bin/sign_update" --ed-key-file - -p "$file")"
printf '%s' "$key" | "$bin/sign_update" --verify --ed-key-file - "$file" "$signature" > /dev/null \
  || die "the signature does not verify"
echo "$signature $(stat -f %z "$file")"
