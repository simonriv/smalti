#!/usr/bin/env bash
# F7.6 C1/C2: from a user without Smalti, installing from the DMG or from a tap opens the app following the documented
# steps. Test build, test bundle ID and state; never /Applications nor the daily Smalti.
#   test-install.sh dmg|brew      prints "[n/total] ok|FAIL <step>"
# The real "Abrir igualmente" click needs the user's password; it is simulated with the approval mark Gatekeeper
# accepts (0x40) and checked by hand at the phase's close (checklist).
set -uo pipefail
mode="${1:?usage: test-install.sh dmg|brew}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
rel="$root/scripts/release"
source "$rel/lib.sh"
source "$rel/test-env.sh"
source "$rel/test-builds.sh"

cache="$root/build/release-test"
work="$(mktemp -d "${TMPDIR:-/tmp}/smalti-install.XXXXXX")"
tap="smaltitest/local"
cleanup() {
  if [[ "$mode" == brew ]]; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask "$tap/smalti" > /dev/null 2>&1  # never --zap
    brew untap "$tap" > /dev/null 2>&1
  fi
  hdiutil detach -quiet "$work/mnt" 2>/dev/null
  test_env_teardown
  rm -rf "$work"
}
trap cleanup EXIT

total=6; n=0; failures=0
step() {
  n=$((n + 1))
  if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"; else echo "[$n/$total] FAIL $1"; failures=$((failures + 1)); fi
}
fatal() { step "$1" 1; exit 1; }

built="$(test_build 0.7.90 "$cache/n" "$(test_keys "$cache")")" || fatal build
"$rel/make-dmg.sh" "$built" "$work/Smalti.dmg" > /dev/null || fatal dmg
step build_and_dmg 0
test_env_setup "$work/home"
apps="$TEST_ROOT/Applications"

# What the browser leaves on a download (Gatekeeper evaluates it at the first open): flags 0x83, no approval.
quarantine_as_download() { xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$1"; }

if [[ "$mode" == dmg ]]; then
  # The documented install: open the DMG and drag Smalti to Aplicaciones.
  mkdir -p "$work/mnt"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mnt" "$work/Smalti.dmg" || fatal mount
  install_copy() { rm -rf "$apps/Smalti.app"; ditto "$work/mnt/Smalti.app" "$apps/Smalti.app"; quarantine_as_download "$apps/Smalti.app"; }
  install_copy
  [[ -L "$work/mnt/Applications" ]]; step dmg_offers_the_applications_link $?
else
  # The documented install: brew install --cask simonriv/tap/smalti, from a local tap with the real template
  # pointed at the local DMG and without zap (never run against this machine's real state).
  tapdir="$work/tap"; mkdir -p "$tapdir/Casks"
  "$rel/cask.sh" 0.7.90 "$(shasum -a 256 "$work/Smalti.dmg" | cut -d' ' -f1)" \
    | sed -e "s#url \".*\"#url \"file://$work/Smalti.dmg\"#" -e '/zap trash:/,/^  \]/d' > "$tapdir/Casks/smalti.rb"
  git -C "$tapdir" init -q && git -C "$tapdir" add -A \
    && git -C "$tapdir" -c user.name=t -c user.email=t@localhost commit -qm cask || fatal tap
  brew tap "$tap" "$tapdir" > /dev/null 2>&1 || fatal tap
  install_copy() {
    HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask "$tap/smalti" > /dev/null 2>&1
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask --appdir="$apps" "$tap/smalti" > "$work/brew.log" 2>&1
  }
  install_copy || fatal brew_install
  [[ "$(xattr -p com.apple.quarantine "$apps/Smalti.app" 2>/dev/null | cut -d';' -f1)" == 0181 ]]
  step brew_quarantines_without_translocation $?
fi

# Gatekeeper's verdict on the quarantined copy: rejected (ad hoc, not notarized), which is the first-open warning.
spctl -a -t exec "$apps/Smalti.app" > /dev/null 2>&1; [[ $? != 0 ]]; step gatekeeper_rejects_the_first_open $?

# Documented step (a): xattr -dr com.apple.quarantine, then open.
xattr -dr com.apple.quarantine "$apps/Smalti.app"
test_env_open "$apps/Smalti.app"; test_env_wait_running "$apps/Smalti.app"; step opens_after_xattr $?
test_env_quit

# Documented step (b): "Abrir igualmente" (simulated: the approval mark it leaves), then open.
install_copy
flags="$(xattr -p com.apple.quarantine "$apps/Smalti.app" | cut -d';' -f1)"
approved="$(printf '%04x' $((16#$flags | 0x40 | 0x100)))"
xattr -w com.apple.quarantine "$approved;$(xattr -p com.apple.quarantine "$apps/Smalti.app" | cut -d';' -f2-)" "$apps/Smalti.app"
test_env_open "$apps/Smalti.app"; test_env_wait_running "$apps/Smalti.app"; step opens_after_abrir_igualmente $?
test_env_quit; step quits $?
exit $((failures > 0))
