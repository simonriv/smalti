#!/usr/bin/env bash
# F7.6: "a user without Smalti" for the install and update tests, without another macOS user: a test bundle ID
# (dev.simonriv.smalti.updatetest) whose defaults point state, config and every harness home at a temporary folder.
# Defaults survive Sparkle's relaunch, launch arguments would not. Sourced by test-install.sh and test-update.sh.

readonly TEST_BUNDLE_ID="dev.simonriv.smalti.updatetest"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# test_env_setup <root>: the folders and the defaults; config with no close confirmation and restore "always".
test_env_setup() {
  mkdir -p "$1"
  # The real path: processes report /private/var/…, while $TMPDIR says /var/… (a symlink).
  local root; root="$(cd "$1" && pwd -P)"
  TEST_ROOT="$root"
  TEST_STATE="$root/state"
  TEST_CONFIG="$root/config/config.toml"
  mkdir -p "$TEST_STATE" "$root/config" "$root/claude" "$root/codex" "$root/antigravity-cli" "$root/opencode" \
    "$root/nvim-config/nvim" "$root/downloads" "$root/Applications"
  printf 'version = 1\n\n[shell]\ncommand = "/bin/zsh -f"\n\n[window]\nconfirm_close = false\n' > "$TEST_CONFIG"
  printf '{ "restore" : "always" }\n' > "$TEST_STATE/preferences.json"
  test_env_clear_defaults
  local d=(defaults write "$TEST_BUNDLE_ID")
  "${d[@]}" SmaltiConfigPath -string "$TEST_CONFIG"
  "${d[@]}" SmaltiStatePath -string "$TEST_STATE"
  "${d[@]}" SmaltiShellCommand -string "/bin/zsh -f"
  "${d[@]}" SmaltiClaudeHome -string "$root/claude"
  "${d[@]}" SmaltiOllamaURL -string "http://127.0.0.1:1"
  "${d[@]}" SmaltiClaudeCommand -string "$root/no-claude"
  "${d[@]}" SmaltiManagedSettings -string "$root/managed-settings.json"
  "${d[@]}" SmaltiCodexHome -string "$root/codex"
  "${d[@]}" SmaltiAntigravityHome -string "$root/antigravity-cli"
  "${d[@]}" SmaltiOpenCodeDB -string "$root/opencode/opencode.db"
  "${d[@]}" SmaltiNvimConfigHome -string "$root/nvim-config/nvim"
  TEST_SOCKETS="/private/tmp/smalti-update-$$"
  "${d[@]}" SmaltiEditorSocketDir -string "$TEST_SOCKETS"
  "${d[@]}" SmaltiDownloadsPath -string "$root/downloads"
}

# Sparkle checks at the next launch and installs on quit without asking (the test plays the user's "Instalar").
test_env_check_on_launch() {
  local d=(defaults write "$TEST_BUNDLE_ID")
  "${d[@]}" SUHasLaunchedBefore -bool YES
  "${d[@]}" SUEnableAutomaticChecks -bool YES
  "${d[@]}" SUAutomaticallyUpdate -bool YES
  "${d[@]}" SULastCheckTime -date "2026-01-01 00:00:00 +0000"
}

test_env_clear_defaults() {
  defaults delete "$TEST_BUNDLE_ID" > /dev/null 2>&1 || true
  rm -rf "$HOME/Library/Caches/$TEST_BUNDLE_ID" "$HOME/Library/HTTPStorages/$TEST_BUNDLE_ID" \
    "$HOME/Library/HTTPStorages/$TEST_BUNDLE_ID.binarycookies" "$HOME/Library/Saved Application State/$TEST_BUNDLE_ID.savedState"
}

# test_env_open <app>: launches it as a user would (LaunchServices, clean environment).
test_env_open() { rm -f "$TEST_STATE/ghostty.conf"; env -i HOME="$HOME" PATH=/usr/bin:/bin open -n "$1"; }

# Waits until the app at <app> runs and has written its engine config into the test state: it opened.
test_env_wait_running() {
  local app="$1" i
  for i in $(seq 1 60); do
    [[ -n "$(test_env_pids)" && -f "$TEST_STATE/ghostty.conf" ]] && return 0
    sleep 0.5
  done
  return 1
}

# PIDs of the test's own app processes, never the daily Smalti: anything run from under the test root, and the
# translocated copies macOS makes of a quarantined test app (the daily one runs from /Applications, untranslocated).
test_env_pids() {
  ps -axo pid=,command= | awk -v root="$TEST_ROOT/" '
    (index($0, root) || /\/AppTranslocation\/[^ ]*\/Smalti\.app\/Contents\/MacOS\/Smalti$/) \
      && /Contents\/MacOS\/Smalti/ { print $1 }'
}

# Whether the test app got past launch: it writes its engine config into the test state.
test_env_started() { [[ -f "$TEST_STATE/ghostty.conf" ]]; }

test_env_quit() {
  # Only when it runs: telling a stopped app to quit would launch some other registered copy of it first.
  [[ -n "$(test_env_pids)" ]] && osascript -e "tell application id \"$TEST_BUNDLE_ID\" to quit" > /dev/null 2>&1
  local i
  for i in $(seq 1 40); do [[ -z "$(test_env_pids)" ]] && return 0; sleep 0.5; done
  return 1
}

# Kills whatever of the test is still running (the app under the test root) and unregisters its copies.
test_env_teardown() {
  local pid
  for pid in $(test_env_pids); do kill -9 "$pid" 2>/dev/null; done
  # Sparkle's installer runs from the test app's cache; it goes before the cache does.
  pkill -f "$HOME/Library/Caches/$TEST_BUNDLE_ID" 2>/dev/null
  [[ -n "${TEST_SOCKETS:-}" ]] && rm -rf "$TEST_SOCKETS"
  find "$TEST_ROOT" -maxdepth 3 -name "*.app" -type d -exec "$lsregister" -u {} \; 2>/dev/null
  test_env_clear_defaults
}
