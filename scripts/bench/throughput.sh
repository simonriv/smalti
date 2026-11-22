#!/usr/bin/env bash
# F0 A12: terminal output throughput. Run it INSIDE the terminal being measured (Smalti, then Ghostty.app).
# Prints the median wall time of `cat` on a 50 MB file and of `seq 1 5000000`.
set -euo pipefail
runs="${1:-5}"
data="${TMPDIR:-/tmp}/smalti-bench-50mb.txt"
[[ -f "$data" ]] || LC_ALL=C tr -dc 'a-zA-Z0-9 \n' < /dev/urandom | head -c 52428800 > "$data"

median() { sort -n | awk '{ v[NR] = $1 } END { print (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2 }'; }
measure() { # label command...
  local label="$1"; shift
  local times=()
  for _ in $(seq "$runs"); do
    times+=("$( { /usr/bin/time -p "$@" > /dev/tty; } 2>&1 | awk '/^real/ { print $2 }')")
  done
  printf '\n%s median=%ss\n' "$label" "$(printf '%s\n' "${times[@]}" | median)"
}

measure cat50mb cat "$data"
measure seq5m seq 1 5000000
