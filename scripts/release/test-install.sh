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
token="smalti-updatetest"  # Caskroom tokens are global: never "smalti", which a real install may own
cleanup() {
  if [[ "$mode" == brew ]]; then
    # Only the test's own token, never --zap: a real `smalti` cask on this machine is never touched.
    HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask "$tap/$token" > /dev/null 2>&1
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
  [[ -z "$(brew list --cask 2>/dev/null | grep -x "$token")" ]] || fatal "a_${token}_cask_is_already_installed"
  tapdir="$work/tap"; mkdir -p "$tapdir/Casks"
  "$rel/cask.sh" 0.7.90 "$(shasum -a 256 "$work/Smalti.dmg" | cut -d' ' -f1)" \
    | sed -e "s#^cask \"smalti\"#cask \"$token\"#" -e "s#url \".*\"#url \"file://$work/Smalti.dmg\"#" \
      -e '/zap trash:/,/^  \]/d' > "$tapdir/Casks/$token.rb"
  git -C "$tapdir" init -q && git -C "$tapdir" add -A \
    && git -C "$tapdir" -c user.name=t -c user.email=t@localhost commit -qm cask || fatal tap
  brew tap "$tap" "$tapdir" > /dev/null 2>&1 || fatal tap
  install_copy() {
    HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask "$tap/$token" > /dev/null 2>&1
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask --appdir="$apps" "$tap/$token" > "$work/brew.log" 2>&1
  }
  install_copy || fatal brew_install
  [[ "$(xattr -p com.apple.quarantine "$apps/Smalti.app" 2>/dev/null | cut -d';' -f1)" == 0181 ]]
  step brew_quarantines_without_translocation $?
fi

# The first open as downloaded: Gatekeeper stops the copy before it runs (the warning the README explains). With
# SMALTI_TEST_FIRST_OPEN=1 the app is really opened and must not start; macOS shows its warning on screen, closed
# by restarting its agent (the phase's close captures it). Without it, only spctl's verdict is checked: it rejects
# every ad hoc build, quarantined or not, so it does not prove the block by itself.
if [[ "${SMALTI_TEST_FIRST_OPEN:-0}" == 1 ]]; then
  test_env_open "$apps/Smalti.app"; sleep 8
  ! test_env_started; step first_open_is_blocked $?
  [[ -n "${SMALTI_TEST_CAPTURE:-}" ]] && screencapture -x "$SMALTI_TEST_CAPTURE"
  killall CoreServicesUIAgent 2>/dev/null
else
  spctl -a -t exec "$apps/Smalti.app" > /dev/null 2>&1; [[ $? != 0 ]]; step gatekeeper_assessment_rejects_ad_hoc $?
fi

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
