#!/usr/bin/env bash
# F7 C2 (final review): Smalti Dev idle with the OTLP receiver off, on, and on with 3 fake Claude emitters
# (`scripts/otlp/fake-claude.py`, a batch every 5 s each) in the background of the pane. Per-process GPU time is not
# available: the app's AGXDeviceUserClient reports an empty `AppUsage` even while drawing. So it samples the system's
# `Device Utilization %` every second, and, to attribute it, the CPU of the app and of WindowServer (who composites).
# Modes run interleaved (off, on, load, off, …) so drift of the machine hits them alike. Debug build, `env -i`,
# temporary config, state, Claude home and managed settings; the probe confirms the receiver's state in each mode.
# Usage: scripts/measure-extras-gpu.sh [rounds]   Prints `[n/total] ok <mode> gpu=… cpu=… windowserver=…` and medians.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rounds="${1:-5}"
settle="${SETTLE_SECONDS:-8}"
window=20
bundle="$root/build/Build/Products/Debug/Smalti Dev.app"
binary="$bundle/Contents/MacOS/Smalti Dev"
xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Debug -derivedDataPath "$root/build" \
  build > "$root/build/measure-extras-gpu-build.log" 2>&1 || { echo "Debug build failed"; exit 1; }
swiftc -O "$root/scripts/gpu-backdrop.swift" -o "$root/build/gpu-backdrop" > /dev/null 2>&1 \
  || { echo "backdrop build failed"; exit 1; }
env -i HOME="$HOME" "$root/build/gpu-backdrop" static &
backdrop_pid=$!
app_pid=""
stop_all() {
  [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null
  kill "$backdrop_pid" 2>/dev/null
  pkill -f "$root/scripts/otlp/fake-claude.py" 2>/dev/null || true
}
trap stop_all EXIT

cpu_seconds() {
  local time; time="$(ps -o time= -p "$1" 2>/dev/null | tr -d ' ' || true)"
  python3 -c "
parts = [float(p) for p in ('$time' or '0:0').replace('-', ':').split(':')]
s = 0.0
for p in parts: s = s * 60 + p
print(s)"
}

modes=(off on load); total=$(( rounds * 3 )); n=0; status=0
results="$(mktemp)"
for round in $(seq 1 "$rounds"); do
  for mode in "${modes[@]}"; do
    n=$((n + 1))
    work="$(mktemp -d)"
    [[ "$mode" == off ]] && printf '[extras]\notlp = false\n' > "$work/config.toml"
    shell="/bin/zsh -f"
    if [[ "$mode" == load ]]; then
      cat > "$work/load.zsh" <<SCRIPT
for i in 1 2 3; do /usr/bin/python3 '$root/scripts/otlp/fake-claude.py' --session load-\$i --requests 100000 --batch 5 --interval 5 >/dev/null 2>&1 & done
exec /bin/zsh -f
SCRIPT
      shell="/bin/zsh -f $work/load.zsh"
    fi
    env -i HOME="$HOME" PATH="/usr/bin:/bin" TMUX=smalti-measure "$binary" \
      -SmaltiStatePath "$work/state" -SmaltiConfigPath "$work/config.toml" -SmaltiShellCommand "$shell" \
      -SmaltiClaudeHome "$work/claude" -SmaltiManagedSettings "$work/managed.json" \
      -SmaltiTelemetryProbe "$work/probe.json" -SmaltiOllamaURL "http://127.0.0.1:1" > "$work/app.log" 2>&1 &
    app_pid=$!
    sleep 2
    open -a "$bundle"
    sleep "$settle"
    expected=listening; [[ "$mode" == off ]] && expected=off
    if ! grep -q "\"status\":\"$expected\"" "$work/probe.json" 2>/dev/null; then
      echo "[$n/$total] FAIL $mode receiver is not $expected ($(cat "$work/probe.json" 2>/dev/null))"; status=1
    else
      ws="$(pgrep -x WindowServer | head -1)"
      c0="$(cpu_seconds "$app_pid")"; w0="$(cpu_seconds "$ws")"; t0="$(python3 -c 'import time; print(time.time())')"
      sum=0
      for _ in $(seq 1 "$window"); do
        value="$(ioreg -r -d 1 -w 0 -c IOAccelerator | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1)"
        sum=$((sum + ${value:-0})); sleep 1
      done
      c1="$(cpu_seconds "$app_pid")"; w1="$(cpu_seconds "$ws")"; t1="$(python3 -c 'import time; print(time.time())')"
      read -r gpu cpu wscpu <<< "$(python3 -c "
span = $t1 - $t0
print(round($sum / $window, 2), round(($c1 - $c0) / span * 100, 2), round(($w1 - $w0) / span * 100, 2))")"
      echo "[$n/$total] ok $mode gpu=${gpu}% cpu=${cpu}% windowserver=${wscpu}%"
      echo "$mode $gpu $cpu $wscpu" >> "$results"
    fi
    kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null; app_pid=""
    pkill -f "$root/scripts/otlp/fake-claude.py" 2>/dev/null || true
    rm -rf "$work"
  done
done
python3 - "$results" <<'PY'
import statistics, sys
rows = [l.split() for l in open(sys.argv[1]) if l.strip()]
for mode in ("off", "on", "load"):
    sel = [r for r in rows if r[0] == mode]
    if sel:
        med = lambda i: statistics.median(float(r[i]) for r in sel)
        print(f"median {mode}: gpu={med(1):.2f}% cpu={med(2):.2f}% windowserver={med(3):.2f}% (n={len(sel)})")
PY
rm -f "$results"
exit "$status"
