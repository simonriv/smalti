#!/usr/bin/env bash
# F5 C6 (issue #5): system GPU use with Smalti Dev open and idle. Builds Debug ("Smalti Dev", its own bundle ID and
# state, never the daily Smalti), launches the binary with a clean environment and `zsh -f` in temporary config and
# state, waits for the window to settle, then averages 10 one-second samples of `Device Utilization %` from ioreg
# (no sudo). `base` measures with no app open. Usage:
#   scripts/measure-gpu-idle.sh [runs] [probe]   probe: base | none | noMask | noShadow | noBlur | noPaneMask | opaque
# Run it inside scripts/check-daily-untouched.sh. Prints `[k/n] ok <probe> <mean>%` per run and the mean of means.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"
probe="${2:-none}"
settle="${SETTLE_SECONDS:-5}"

sample_gpu() { # prints the mean of 10 one-second samples
  local total=0 value
  for _ in $(seq 1 10); do
    value="$(ioreg -r -d 1 -w 0 -c IOAccelerator | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1)"
    total=$((total + ${value:-0}))
    sleep 1
  done
  python3 -c "print(round($total / 10, 1))"
}

if [[ "$probe" != base ]]; then
  xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Debug -derivedDataPath "$root/build" \
    build > "$root/build/measure-gpu-build.log" 2>&1 || { echo "Debug build failed (build/measure-gpu-build.log)"; exit 1; }
fi
binary="$root/build/Build/Products/Debug/Smalti Dev.app/Contents/MacOS/Smalti Dev"

sum=0
for run in $(seq 1 "$runs"); do
  if [[ "$probe" == base ]]; then
    sleep "$settle"
    mean="$(sample_gpu)"
  else
    work="$(mktemp -d)"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" TMUX=smalti-measure "$binary" \
      -SmaltiStatePath "$work/state" -SmaltiConfigPath "$work/config.toml" \
      -SmaltiShellCommand "/bin/zsh -f" -SmaltiGlassProbe "$probe" > "$work/app.log" 2>&1 &
    app_pid=$!
    # Block 1 review (M7): a failure under `set -e` must not leave Smalti Dev open.
    trap 'kill "$app_pid" 2>/dev/null || true' EXIT
    sleep "$settle"
    if ! kill -0 "$app_pid" 2>/dev/null; then echo "[$run/$runs] FAIL $probe app exited"; exit 1; fi
    mean="$(sample_gpu)"
    kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true
    rm -rf "$work"
  fi
  echo "[$run/$runs] ok $probe ${mean}%"
  sum="$(python3 -c "print($sum + $mean)")"
done
echo "mean $probe: $(python3 -c "print(round($sum / $runs, 1))")% (criterion C6: <= 10%)"
