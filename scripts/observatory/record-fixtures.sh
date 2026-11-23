#!/usr/bin/env bash
# F3 T6: records real Claude Code sessions unattended with `claude -p` and turns them into committable fixtures.
# Usage: scripts/observatory/record-fixtures.sh <fixtures-dir>
#   A: one turn · B: three turns with --resume and tools (Bash ls, Read) · C: a subagent (Task/Agent) ·
#   F: a --fork-session of A (to learn whether forks copy message ids).
# Sessions run in a fresh directory outside $HOME, with the user's settings layer and MCP servers off, from a
# clean environment (no CLAUDE_CODE_* markers of the calling session). Transcripts go through sanitize_fixture.py,
# then the independent oracle writes expected.json. The `status` values seen in ~/.claude/sessions are kept in
# statuses.txt (only that key is read; *.key files are never touched).
set -euo pipefail
out="${1:?usage: $0 <fixtures-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
claude_bin="$(command -v claude)"
work="$(mktemp -d "${TMPDIR:-/tmp}/smalti-rec.XXXXXX")"
work="$(cd "$work" && pwd -P)"
model="claude-haiku-5-5"
statuses="$work/statuses.txt"; : > "$statuses"
# Compared without case or accents (sanitize_fixture.scan): any of these left in a fixture stops the recording.
markers=(--marker "Simón" --marker "Rivera" --marker "Agudelo" --marker "simonriv" --marker "srivera"
  --marker "Protección" --marker "xolken" --marker "@gmail" --marker "Bello" --marker "Medellín")

run() { # run <dir> <prompt> <claude args…>: a clean-environment claude -p in <dir>, JSON result on stdout.
  # The prompt goes right after -p: --allowedTools takes every following word as a tool name.
  local dir="$1" prompt="$2"; shift 2
  (cd "$dir" && env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh TMPDIR="$TMPDIR" LANG=es_CO.UTF-8 \
    PATH="$(dirname "$claude_bin"):/usr/bin:/bin:/usr/sbin:/sbin" \
    "$claude_bin" -p "$prompt" --model "$model" --setting-sources project --strict-mcp-config --output-format json "$@")
}

watch_statuses() { # keeps the status of sessions whose cwd is under $work while recordings run
  while :; do
    for file in "$HOME"/.claude/sessions/*.json; do
      [[ -f "$file" ]] || continue
      python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
if str(d.get("cwd","")).startswith(sys.argv[2]): print(d.get("status",""))' "$file" "$work" 2>/dev/null >> "$statuses" || true
    done
    sleep 0.2
  done
}
session_id() { python3 -I -c 'import json,sys; print(json.load(sys.stdin)["session_id"])'; }

mkdir -p "$work/a" "$work/b" "$work/c"
touch "$work/b/uno.txt" "$work/b/dos.txt" "$work/c/tres.txt" "$work/c/cuatro.txt"
watch_statuses & watcher=$!
trap 'kill $watcher 2>/dev/null || true' EXIT

a=$(run "$work/a" "Responde solo con la palabra: hola" | session_id)
b=$(run "$work/b" "Lista los archivos de este directorio con ls y responde solo cuántos hay." \
  --allowedTools "Bash(ls:*)" | session_id)
run "$work/b" "Lee uno.txt con la herramienta Read y responde solo si está vacío." --resume "$b" \
  --allowedTools "Read" > /dev/null
run "$work/b" "Responde solo: listo" --resume "$b" > /dev/null
c=$(run "$work/c" "Usa la herramienta Task (o Agent) para lanzar un subagente general-purpose que cuente con ls los \
archivos .txt de este directorio. Luego responde solo con el número." --allowedTools "Task" "Agent" "Bash(ls:*)" | session_id)
f=$(run "$work/a" "Responde solo: adiós" --resume "$a" --fork-session | session_id)
kill $watcher 2>/dev/null || true

projects="$out/projects"
rm -rf "$projects"; mkdir -p "$projects"
encode() { printf '%s' "$1" | sed 's|[^A-Za-z0-9]|-|g'; }
for pair in "a:$a" "a:$f" "b:$b" "c:$c"; do
  dir="${pair%%:*}"; id="${pair#*:}"
  source_dir="$HOME/.claude/projects/$(encode "$work/$dir")"
  target_dir="$projects/-fixture-work-$dir"; mkdir -p "$target_dir"
  python3 -I "$here/sanitize_fixture.py" "$source_dir/$id.jsonl" "$target_dir/$id.jsonl" \
    --work "$work" --home "$HOME" "${markers[@]}"
  if [[ -d "$source_dir/$id/subagents" ]]; then
    mkdir -p "$target_dir/$id/subagents"
    for sub in "$source_dir/$id/subagents/"*.jsonl; do
      python3 -I "$here/sanitize_fixture.py" "$sub" "$target_dir/$id/subagents/$(basename "$sub")" \
        --work "$work" --home "$HOME" "${markers[@]}"
    done
  fi
done
# A fork copies its source's message ids (verified 2026-11-23, Claude Code 2.1.330): the count is global.
python3 -I "$here/sum_transcripts.py" "$projects" --global-dedupe > "$out/expected.json"
sort -u "$statuses" | grep -v '^$' > "$out/statuses.txt" || true
printf 'A=%s\nB=%s\nC=%s\nF(fork of A)=%s\n' "$a" "$b" "$c" "$f" > "$out/sessions.txt"
echo "recorded into $out (work dir $work)"
