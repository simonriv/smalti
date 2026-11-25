#!/usr/bin/env bash
# F7 C2: F0's throughput (A12, `scripts/bench/throughput.sh` inside the pane) and idle memory (A14, `footprint`)
# of Smalti Dev with the OTLP receiver off, on, and on with 3 fake Claude emitters (`scripts/otlp/fake-claude.py`,
# one batch every 5 s each) in the background of the measured pane. Debug build, clean environment (`env -i`),
# temporary config, state and Claude home, `zsh -f`. Never the daily Smalti nor the user's ~/.claude.
# Usage: scripts/measure-extras.sh [runs] [modes…]   modes: off on load (default: all three)
# Prints `[n/total] ok <mode> cat50mb=… seq5m=… footprint=…MB` per run and the medians per mode.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-5}"; shift || true
modes=("$@"); (( ${#modes[@]} )) || modes=(off on load)
bundle="$root/build/Build/Products/Debug/Smalti Dev.app"
binary="$bundle/Contents/MacOS/Smalti Dev"
xcodebuild -project "$root/App/Smalti.xcodeproj" -scheme Smalti -configuration Debug -derivedDataPath "$root/build" \
  build > "$root/build/measure-extras-build.log" 2>&1 || { echo "Debug build failed (build/measure-extras-build.log)"; exit 1; }
# throughput.sh makes its 50 MB file on first use under `set -o pipefail`, and `tr`'s SIGPIPE ends it there: make
# it beforehand (the panes run with `env -i`, so TMPDIR is unset and the file lives in /tmp).
data=/tmp/smalti-bench-50mb.txt
[[ -s "$data" ]] || LC_ALL=C python3 -c "
import random, string; random.seed(7); chars = string.ascii_letters + string.digits + ' \n'
open('$data', 'w').write(''.join(random.choice(chars) for _ in range(52428800)))"
app_pid=""
stop_all() {
  [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null
  pkill -f "$root/scripts/otlp/fake-claude.py" 2>/dev/null || true
}
trap stop_all EXIT

total=$(( runs * ${#modes[@]} )); n=0; status=0
results="$(mktemp)"
for mode in "${modes[@]}"; do
  for run in $(seq 1 "$runs"); do
    n=$((n + 1))
    work="$(mktemp -d)"
    [[ "$mode" == off ]] && printf '[extras]\notlp = false\n' > "$work/config.toml"
    emitters=""
    if [[ "$mode" == load ]]; then
      emitters="for i in 1 2 3; do /usr/bin/python3 '$root/scripts/otlp/fake-claude.py' --session load-\$i --requests 100000 --batch 5 --interval 5 >/dev/null 2>&1 & done; "
    fi
    cat > "$work/run.zsh" <<SCRIPT
$emitters
sleep 6
touch '$work/ready'
while [[ ! -f '$work/go' ]]; do sleep 0.2; done
'$root/scripts/bench/throughput.sh' 5 > '$work/throughput.txt' 2> '$work/throughput.err'
touch '$work/done'
SCRIPT
    env -i HOME="$HOME" PATH="/usr/bin:/bin" TMUX=smalti-measure "$binary" \
      -SmaltiStatePath "$work/state" -SmaltiConfigPath "$work/config.toml" \
      -SmaltiShellCommand "/bin/zsh -f $work/run.zsh" \
      -SmaltiClaudeHome "$work/claude" -SmaltiManagedSettings "$work/managed.json" \
      -SmaltiOllamaURL "http://127.0.0.1:1" > "$work/app.log" 2>&1 &
    app_pid=$!
    sleep 2
    open -a "$bundle"
    for _ in $(seq 1 60); do [[ -f "$work/ready" ]] && break; sleep 1; done
    # Idle memory of the app itself (A14), before the output: the shell's parent may be `login`, not the app.
    /usr/bin/footprint -p "$app_pid" 2>/dev/null | awk '/phys_footprint:/ { print $2, $3 }' > "$work/footprint.txt"
    touch "$work/go"
    for _ in $(seq 1 600); do [[ -f "$work/done" ]] && break; sleep 1; done
    kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null; app_pid=""
    pkill -f "$root/scripts/otlp/fake-claude.py" 2>/dev/null || true
    cat50="$(sed -n 's/^cat50mb median=\(.*\)s$/\1/p' "$work/throughput.txt")"
    seq5="$(sed -n 's/^seq5m median=\(.*\)s$/\1/p' "$work/throughput.txt")"
    foot="$(cat "$work/footprint.txt" 2>/dev/null)"
    if [[ -n "$cat50" && -n "$seq5" ]]; then
      echo "[$n/$total] ok $mode cat50mb=${cat50}s seq5m=${seq5}s footprint=${foot}"
      echo "$mode $cat50 $seq5 ${foot%% *}" >> "$results"
    else
      echo "[$n/$total] FAIL $mode no result (see $work)"; status=1; continue
    fi
    rm -rf "$work"
  done
done
python3 - "$results" <<'PY'
import statistics, sys
rows = [line.split() for line in open(sys.argv[1]) if line.strip()]
for mode in ("off", "on", "load"):
    sel = [r for r in rows if r[0] == mode]
    if not sel: continue
    med = lambda i: statistics.median(float(r[i]) for r in sel if len(r) > i and r[i] not in ("", "None"))
    print(f"median {mode}: cat50mb={med(1):.3f}s seq5m={med(2):.3f}s footprint={med(3):.0f}")
PY
rm -f "$results"
exit "$status"
