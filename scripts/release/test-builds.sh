#!/usr/bin/env bash
# F7.6: the two test builds the install and update tests share (sourced): versions 0.7.90 (N) and 0.7.91 (N+1)
# with the test bundle ID, a feed on 127.0.0.1:$TEST_PORT and the test's public EdDSA key. Rebuilt only when the
# commit, the port or the key changed.
readonly TEST_PORT="${TEST_PORT:-28766}"
readonly TEST_FEED="http://127.0.0.1:$TEST_PORT/appcast.xml"

# test_build <version> <out dir> <public key>: prints the built app.
test_build() {
  local version="$1" out="$2" key="$3" root stamp
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  stamp="$(git -C "$root" rev-parse HEAD)$(git -C "$root" diff --quiet HEAD || echo -dirty) $TEST_PORT $key"
  if [[ -d "$out/Smalti.app" && "$(cat "$out/stamp" 2>/dev/null)" == "$stamp" ]]; then echo "$out/Smalti.app"; return; fi
  SMALTI_VERSION="$version" SMALTI_BUNDLE_ID="$TEST_BUNDLE_ID" SMALTI_FEED_URL="$TEST_FEED" \
    SMALTI_ED_PUBLIC_KEY="$key" "$root/scripts/release/build.sh" "v$version" "$out" > /dev/null || return 1
  echo "$stamp" > "$out/stamp"
  echo "$out/Smalti.app"
}

# The test's throwaway EdDSA keys, kept with the cached builds: "good" signs the updates, "other" the refused one.
# Prints the public key of "good".
test_keys() {
  local cache="$1" name
  mkdir -p "$cache/keys"
  for name in good other; do
    [[ -s "$cache/keys/$name" ]] || openssl genpkey -algorithm ed25519 2>/dev/null \
      | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64 > "$cache/keys/$name"
  done
  "$(dirname "${BASH_SOURCE[0]}")/public-key.sh" < "$cache/keys/good"
}
