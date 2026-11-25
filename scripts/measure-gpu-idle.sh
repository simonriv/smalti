#!/usr/bin/env bash
# F5 C6 (issue #5): system GPU use with Smalti Dev open and idle. Builds Debug ("Smalti Dev", its own bundle ID and
# state, never the daily Smalti), launches the binary with a clean environment and `zsh -f` in temporary config and
# state (and an empty Claude home: never the real ~/.claude), waits for the window to settle, then averages 10 one-second samples of `Device Utilization %` from ioreg
# (no sudo). `base` measures with no app open. Each run leaves a capture in build/measure-gpu-<probe>-<k>.png to
# check the window was in front. Usage:
#   scripts/measure-gpu-idle.sh [runs] [probe]   probe: base | none | noMask | noShadow | noBlur | noPaneMask | opaque
# Run it inside scripts/check-daily-untouched.sh. Prints `[k/n] ok <probe> <mean>%` per run and the mean of means.
# BACKDROP=static (default) | moving | none: first opens scripts/gpu-backdrop.swift, a full-screen window under the app
# that hides the rest of the desktop (T13: a translucent terminal redrawing behind took the bare baseline to ~40 %).
# `moving` animates it, so the glass must recomposite what changes behind it: the case that reached ~25 % in daily use.
# Each line also gives the mean CPU of Smalti Dev and of WindowServer (who does the work).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"
probe="${2:-none}"
settle="${SETTLE_SECONDS:-5}"

cpu_seconds() { # user+system CPU time of a pid in seconds (0 if it is gone)
  local time
  time="$(ps -o time= -p "$1" 2>/dev/null | tr -d ' ' || true)"
  python3 -c "
t = '$time' or '0:0'
parts = [float(p) for p in t.replace('-', ':').split(':')]
seconds = 0.0
for part in parts: seconds = seconds * 60 + part
print(seconds)"
}

# Prints "<gpu mean> <app cpu %> <WindowServer cpu %>" over 10 one-second samples; CPU from the time each process
# used during the window (ps's %cpu is a decaying average that still carries the launch).
sample_gpu() {
  local total=0 value ws_pid app_start ws_start started finished
  ws_pid="$(pgrep -x WindowServer | head -1)"
  app_start="$(cpu_seconds "${app_pid:-0}")"
  ws_start="$(cpu_seconds "$ws_pid")"
  started="$(python3 -c 'import time; print(time.time())')"
  for _ in $(seq 1 10); do
    value="$(ioreg -r -d 1 -w 0 -c IOAccelerator | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1)"
    total=$((total + ${value:-0}))
    sleep 1
  done
  finished="$(python3 -c 'import time; print(time.time())')"
  python3 -c "
span = $finished - $started
print(round($total / 10, 1), round(($(cpu_seconds "${app_pid:-0}") - $app_start) / span * 100, 1),
      round(($(cpu_seconds "$ws_pid") - $ws_start) / span * 100, 1))"
}

if [[ "$probe" != base ]]; then
  xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Debug -derivedDataPath "$root/build" \
    build > "$root/build/measure-gpu-build.log" 2>&1 || { echo "Debug build failed (build/measure-gpu-build.log)"; exit 1; }
fi
bundle="$root/build/Build/Products/Debug/Smalti Dev.app"
binary="$bundle/Contents/MacOS/Smalti Dev"

backdrop="${BACKDROP:-static}"
backdrop_pid=""
probe_label="$probe"
if [[ "$backdrop" != none ]]; then
  mkdir -p "$root/build"
  swiftc -O "$root/scripts/gpu-backdrop.swift" -o "$root/build/gpu-backdrop" \
    > "$root/build/measure-gpu-backdrop.log" 2>&1 || { echo "backdrop build failed"; exit 1; }
  env -i HOME="$HOME" "$root/build/gpu-backdrop" "$backdrop" &
  backdrop_pid=$!
  probe_label="$probe+$backdrop"
fi
stop_all() { kill ${app_pid:-} $backdrop_pid 2>/dev/null || true; }
trap stop_all EXIT

sum=0
for run in $(seq 1 "$runs"); do
  if [[ "$probe" == base ]]; then
    sleep "$settle"
    read -r mean app_cpu ws_cpu <<< "$(sample_gpu)"
  else
    work="$(mktemp -d)"
    # F7 C2: OTLP=off measures with the telemetry receiver off (on by default).
    [[ "${OTLP:-on}" == off ]] && printf '[extras]\notlp = false\n' > "$work/config.toml"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" TMUX=smalti-measure "$binary" \
      -SmaltiStatePath "$work/state" -SmaltiConfigPath "$work/config.toml" \
      -SmaltiShellCommand "/bin/zsh -f" -SmaltiGlassProbe "$probe" \
      -SmaltiClaudeHome "$work/claude" -SmaltiOllamaURL "http://127.0.0.1:1" > "$work/app.log" 2>&1 &
    app_pid=$!
    # A binary launched from a shell does not take the front: without this the window sits behind the terminal and
    # the measure says nothing about the glass (T13 found T1's numbers taken that way). `open -a` on the running
    # bundle only activates it.
    sleep 2
    open -a "$bundle"
    # Block 1 review (M7): a failure under `set -e` must not leave Smalti Dev open (`stop_all` on EXIT).
    sleep "$settle"
    if ! kill -0 "$app_pid" 2>/dev/null; then echo "[$run/$runs] FAIL $probe_label app exited"; exit 1; fi
    read -r mean app_cpu ws_cpu <<< "$(sample_gpu)"
    screencapture -x "$root/build/measure-gpu-$probe_label-$run.png"
    kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; app_pid=""
    rm -rf "$work"
  fi
  echo "[$run/$runs] ok $probe_label ${mean}% (cpu app ${app_cpu}%, WindowServer ${ws_cpu}%)"
  sum="$(python3 -c "print($sum + $mean)")"
done
echo "mean $probe_label: $(python3 -c "print(round($sum / $runs, 1))")% (criterion C6: <= 10%)"
