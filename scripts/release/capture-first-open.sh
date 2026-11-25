#!/usr/bin/env bash
# F7.6: the two screenshots of the first open on real macOS 27, for the README and the web: the warning when the
# downloaded app is opened, and "Privacidad y seguridad" with "Abrir igualmente". Uses the test build and state
# (never /Applications/Smalti.app) and captures only those windows, never the whole screen.
#   capture-first-open.sh <out dir> <window lister binary>
# The lister prints "id<TAB>owner<TAB>…" for the on-screen windows of an owner (scratch helper, CGWindowList).
set -uo pipefail
out="${1:?out dir}"; lister="${2:?window lister}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
rel="$root/scripts/release"
source "$rel/lib.sh"
source "$rel/test-env.sh"
source "$rel/test-builds.sh"
cache="$root/build/release-test"
work="$(mktemp -d "${TMPDIR:-/tmp}/smalti-capture.XXXXXX")"
cleanup() {
  killall CoreServicesUIAgent 2>/dev/null
  osascript -e 'tell application id "com.apple.systempreferences" to quit' > /dev/null 2>&1
  test_env_teardown
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$out"

built="$(test_build 0.7.90 "$cache/n" "$(test_keys "$cache")")" || die "build failed"
test_env_setup "$work/home"
app="$TEST_ROOT/Applications/Smalti.app"
ditto "$built" "$app"
# As the README flow leaves it: downloaded (0x01, 0x80) and dragged to Applications by Finder (0x100, no translocation).
xattr -w com.apple.quarantine "0183;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$app"

window_of() { # owner -> the id of its frontmost on-screen window
  local i id
  for i in $(seq 1 30); do
    id="$("$lister" "$1" | head -1 | cut -f1)"
    [[ -n "$id" ]] && { echo "$id"; return 0; }
    sleep 0.5
  done
  return 1
}

test_env_open "$app"
dialog="$(window_of CoreServicesUIAgent)" || die "no first-open warning appeared"
sleep 1
screencapture -x -o -l "$dialog" "$out/first-open-warning.png"
test_env_started && die "the quarantined app started: no Gatekeeper block"
# The panel offers "Abrir de todos modos" only after the user dismisses the warning, as the README says.
osascript > /dev/null 2>&1 <<'AS' || die "could not press the warning's button"
tell application "System Events" to tell process "CoreServicesUIAgent"
  repeat with title in {"Listo", "Aceptar", "Done"}
    if exists button (title as text) of window 1 then
      click button (title as text) of window 1
      return
    end if
  end repeat
  error "no button"
end tell
AS
sleep 1

open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security"
settings="$(window_of "Configuración del Sistema")" || settings="$(window_of "Ajustes del Sistema")" \
  || settings="$(window_of "System Settings")" || die "no System Settings window"
sleep 6
# The window also shows the user's Apple account (name, photo): only the "Seguridad" block is kept. Its place is
# found in a full capture of the window and passed as SMALTI_CAPTURE_CROP="<y> <x> <height> <width>" (pixels).
screencapture -x -o -l "$settings" "$work/settings.png"
if [[ -n "${SMALTI_CAPTURE_CROP:-}" ]]; then
  read -r y x h w <<< "$SMALTI_CAPTURE_CROP"
  sips --cropOffset "$y" "$x" -c "$h" "$w" "$work/settings.png" --out "$out/privacy-security-open-anyway.png" > /dev/null
else
  cp "$work/settings.png" "$out/settings-uncropped.png"
fi
ls -la "$out"
