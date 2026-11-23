#!/usr/bin/env bash
# F2 C6: time from launch until the last restored pane is interactive, with 3 workspaces and 6 panes of 10,000
# scrollback lines each. Builds Release, seeds a temporary state directory and launches the app binary directly
# (no XCUITest, the daily Smalti is untouched), reads the end of the `restore` signpost from the unified log, and
# prints one line per run plus the worst case. Usage: scripts/measure-restore.sh [runs]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"
xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Release -derivedDataPath "$root/build" \
  build > "$root/build/measure-restore-build.log" 2>&1 || { echo "Release build failed"; exit 1; }
binary="$root/build/Build/Products/Release/Smalti.app/Contents/MacOS/Smalti"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$root/build/Build/Products/Release/Smalti.app" 2>/dev/null || true

seed() { # state directory
  local state="$1" panes="" ws="" ids=()
  mkdir -p "$state/scrollback"
  local text; text="$(for i in $(seq 1 10000); do printf 'línea %05d de salida guardada para medir la restauración\n' "$i"; done)"
  for w in 0 1 2; do
    panes=""
    for p in 0 1; do
      local id; id="$(uuidgen)"
      { printf 'P'; printf '%s' "$text"; } | compression_tool -encode -a lzfse -o "$state/scrollback/$id.lzfse"
      panes+="${panes:+,}{\"id\":\"$id\",\"workingDirectory\":\"/tmp\",\"scrollbackLines\":10000,\"commandCount\":0}"
    done
    ws+="${ws:+,}{\"name\":\"w$w\",\"rootDirectory\":\"/tmp\",\"layout\":\"dwindle\",\"focusedIndex\":0,\"panes\":[$panes]}"
  done
  printf '{"version":1,"savedAt":"2026-11-22T20:00:00Z","activeIndex":0,"workspaces":[%s]}' "$ws" > "$state/session.json"
  printf '{"restore":"always"}' > "$state/preferences.json"
}

worst=0
for run in $(seq 1 "$runs"); do
  work="$(mktemp -d)"; state="$work/state"; zdot="$work/zdotdir"; mkdir -p "$zdot"
  seed "$state"
  log stream --style compact --signpost --predicate 'category == "restore"' > "$work/signposts.txt" 2>&1 &
  logger_pid=$!
  sleep 1
  started="$(python3 -c 'import time; print(time.time())')"
  ZDOTDIR="$zdot" TMUX=smalti-measure "$binary" -SmaltiStatePath "$state" -SmaltiShellCommand /bin/zsh \
    -SmaltiConfigPath "$work/config.toml" > "$work/app.log" 2>&1 &
  app_pid=$!
  ended=""
  for _ in $(seq 1 300); do
    if grep -q 'end.*restore\|restore.*end\|Event: end' "$work/signposts.txt" 2>/dev/null; then
      ended="$(python3 -c 'import time; print(time.time())')"; break
    fi
    sleep 0.05
  done
  kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true
  kill "$logger_pid" 2>/dev/null || true
  if [[ -z "$ended" ]]; then echo "[$run/$runs] FAIL restore did not finish in 15 s"; worst=99; continue; fi
  seconds="$(python3 -c "print(round($ended - $started, 2))")"
  echo "[$run/$runs] ok ${seconds} s"
  worst="$(python3 -c "print(max($worst, $seconds))")"
  rm -rf "$work"
done
echo "worst: ${worst} s (criterion: < 5 s)"
python3 -c "import sys; sys.exit(0 if $worst < 5 else 1)"
