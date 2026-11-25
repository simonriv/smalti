#!/usr/bin/env bash
# F7.6 C3/C4: an installed Smalti updates itself from an appcast on 127.0.0.1, without a Gatekeeper prompt and
# without losing its session, layouts or configuration (valid); an update signed with another key is refused and
# leaves the app as it was (invalid). Test builds and state only: never /Applications/Smalti.app nor its state.
#   test-update.sh valid|invalid      prints "[n/total] ok|FAIL <step>"
set -uo pipefail
mode="${1:?usage: test-update.sh valid|invalid}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
rel="$root/scripts/release"
source "$rel/lib.sh"
source "$rel/test-env.sh"
source "$rel/test-builds.sh"

cache="$root/build/release-test"
work="$(mktemp -d "${TMPDIR:-/tmp}/smalti-update.XXXXXX")"
server=""
cleanup() {
  [[ -n "$server" ]] && kill "$server" 2>/dev/null && wait "$server" 2>/dev/null
  test_env_teardown
  rm -rf "$work"
}
trap cleanup EXIT

total=$([[ "$mode" == valid ]] && echo 8 || echo 5); n=0; failures=0
step() { # name status
  n=$((n + 1))
  if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"; else echo "[$n/$total] FAIL $1"; failures=$((failures + 1)); fi
}
fatal() { step "$1" 1; exit 1; }

public="$(test_keys "$cache")" || fatal keys
old_app="$(test_build 0.7.90 "$cache/n" "$public")" || fatal build_version_n
new_app="$(test_build 0.7.91 "$cache/n1" "$public")" || fatal build_version_n_plus_1
step builds_n_and_n_plus_1 0

# The update: N+1's DMG, signed with the right or the wrong key, behind a local appcast.
feed="$work/feed"; mkdir -p "$feed"
"$rel/make-dmg.sh" "$new_app" "$feed/Smalti.dmg" > /dev/null || fatal dmg
key="$cache/keys/$([[ "$mode" == valid ]] && echo good || echo other)"
SPARKLE_BIN="${SPARKLE_BIN:-$("$rel/fetch-sparkle-tools.sh" "$cache/sparkle")}"; export SPARKLE_BIN
read -r signature length < <("$rel/sign-update.sh" "$feed/Smalti.dmg" < "$key") || fatal sign
SMALTI_DOWNLOAD_URL="http://127.0.0.1:$TEST_PORT/Smalti.dmg" SMALTI_NOTES_URL="http://127.0.0.1:$TEST_PORT/notes.html" \
  "$rel/appcast-item.sh" 0.7.91 "$length" "$signature" > "$feed/item.xml"
sed "/prepends one <item>/r $feed/item.xml" "$rel/templates/appcast-empty.xml" > "$feed/appcast.xml"
printf '<p>0.7.91</p>\n' > "$feed/notes.html"

# A user who installed N from the DMG and opened it with "Abrir igualmente": the app sits in "Aplicaciones" with
# the quarantine Gatekeeper approved (0x40) and no translocation (0x100), which is what Finder's drag leaves.
test_env_setup "$work/home"
app="$TEST_ROOT/Applications/Smalti.app"
ditto "$old_app" "$app"
xattr -w com.apple.quarantine "01c3;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$app"

# Session, layout and configuration made by N, before any update is offered.
test_env_open "$app"; test_env_wait_running "$app" || fatal version_n_opens
test_env_quit || fatal version_n_quits
python3 - "$TEST_STATE/session.json" <<'P' || fatal seed_session
import json, sys
path = sys.argv[1]
session = json.load(open(path))
window = session["windows"][0]
second = json.loads(json.dumps(window["workspaces"][0]))
second["name"] = "segundo"
window["workspaces"].append(second)
json.dump(session, open(path, "w"), indent=2, sort_keys=True)
P
mkdir -p "$TEST_STATE/layouts"
python3 - "$TEST_STATE/session.json" "$TEST_STATE/layouts/prueba.json" <<'P'
import json, sys
workspace = json.load(open(sys.argv[1]))["windows"][0]["workspaces"][0]
workspace["version"] = 1
json.dump(workspace, open(sys.argv[2], "w"), indent=2, sort_keys=True)
P
printf '\n[appearance]\nfont_size = 15\n' >> "$TEST_CONFIG"
printf 'version = 1\n\n[appearance]\nblur = 20\n' > "$TEST_ROOT/config/theme.toml"
test_env_open "$app"; test_env_wait_running "$app" || fatal version_n_reopens
test_env_quit || fatal version_n_quits_again
workspaces() { python3 -c 'import json,sys; print(" ".join(sorted(w["name"] for w in json.load(open(sys.argv[1]))["windows"][0]["workspaces"])))' "$TEST_STATE/session.json"; }
before_workspaces="$(workspaces)"
fingerprint() { shasum -a 256 "$TEST_STATE/layouts/prueba.json" "$TEST_CONFIG" "$TEST_ROOT/config/theme.toml" | cut -d' ' -f1; }
before_files="$(fingerprint)"
before_binary="$(shasum -a 256 "$app/Contents/MacOS/Smalti" | cut -d' ' -f1)"

session_stamp="$(stat -f %m "$TEST_STATE/session.json")"
sleep 1  # the next save must get a later modification time

# The check: N finds N+1 at launch, downloads it in the background and installs it when the user quits.
python3 -m http.server "$TEST_PORT" --bind 127.0.0.1 --directory "$feed" > "$work/http.log" 2>&1 &
server=$!
for _ in $(seq 1 20); do curl -fs "$TEST_FEED" > /dev/null && break; sleep 0.25; done
test_env_check_on_launch
test_env_open "$app"; test_env_wait_running "$app" || fatal version_n_opens_with_the_feed
for _ in $(seq 1 60); do grep -q "GET /Smalti.dmg" "$work/http.log" && break; sleep 0.5; done
sleep 3  # Sparkle verifies and extracts the download before it schedules the install
test_env_quit || fatal version_n_quits_for_the_update
version() { plutil -extract CFBundleVersion raw "$app/Contents/Info.plist" 2>/dev/null; }
if [[ "$mode" == valid ]]; then
  for _ in $(seq 1 60); do [[ "$(version)" == 791 ]] && break; sleep 1; done
else
  sleep 10  # the refusal is immediate; give the installer time to have done anything it would
fi

if [[ "$mode" == invalid ]]; then
  grep -q "GET /Smalti.dmg" "$work/http.log"; step downloaded_the_update $?
  # Sparkle's own reason, as SparkleUpdates logs it: SUSparkleErrorDomain 4005 (signature does not match).
  log show --last 5m --style compact \
    --predicate "subsystem == \"$TEST_BUNDLE_ID\" AND category == \"updates\"" 2>/dev/null \
    | grep -q "update aborted: SUSparkleErrorDomain 4005" && [[ "$(version)" == "$(build_number 0.7.90)" ]]
  step refused_the_wrong_signature $?
  [[ "$(shasum -a 256 "$app/Contents/MacOS/Smalti" | cut -d' ' -f1)" == "$before_binary" ]]; step app_left_identical $?
  [[ "$(fingerprint)" == "$before_files" ]]; step state_untouched $?
  exit $((failures > 0))
fi

[[ "$(version)" == "$(build_number 0.7.91)" ]]; step installed_n_plus_1 $?
[[ "$(xattr -r -l "$app" 2>/dev/null | grep -c com.apple.quarantine)" == 0 ]]; step no_quarantine_after_the_update $?
test_env_open "$app"; test_env_wait_running "$app"; step opens_without_gatekeeper $?
test_env_quit; step quits $?
# Restored and saved again by N+1: the same workspaces, in a session.json written after the update.
[[ "$(workspaces)" == "$before_workspaces" && "$before_workspaces" == *segundo* \
  && "$(stat -f %m "$TEST_STATE/session.json")" -gt "$session_stamp" ]]; step session_restored $?
[[ "$(fingerprint)" == "$before_files" ]]; step layout_and_configuration_untouched $?
requests="$(sed -nE 's/.*"GET ([^ ]+) HTTP.*/\1/p' "$work/http.log" | sort -u | tr '\n' ' ')"
[[ "$requests" =~ ^(/Smalti.dmg\ |/appcast.xml\ |/notes.html\ )+$ ]]; step only_the_feed_was_requested $?
echo "requests: $requests"
exit $((failures > 0))
