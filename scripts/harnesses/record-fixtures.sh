#!/bin/zsh
# Records real sessions of one harness for F6's fixtures (spec F6, "Fixtures reales").
#
#   scripts/harnesses/record-fixtures.sh <claude|codex|antigravity|opencode|codex-timeline>
#
# Everything runs under the fixed paths the tests use, /private/tmp/smalti-fx/<harness>/{home,work-a,work-b}:
# harnesses keep paths inside protobuf blobs, so the fixture keeps them instead of rewriting them. Two sessions are
# recorded, one per work directory. The raw home (with login tokens) is kept in scripts/harnesses/recording.local/
# (git-ignored); the committed fixture is its sanitized copy, written by sanitize_fixture.py.
#
# - codex and opencode talk to a local Ollama with qwen3:4b (free). If none answers on 127.0.0.1:11434, one is
#   started on 127.0.0.1:11435 and stopped at the end.
# - antigravity needs a login: put a logged-in home in recording.local/antigravity/login-home first (see the spec).
# - claude reuses F3's real transcripts (paid recordings are not repeated), moved to the fixed paths.
# - codex-timeline (F9) records one Codex session of two turns that runs shell tools, one of them failing, in work-a.
set -euo pipefail

harness=${1:?usage: record-fixtures.sh <claude|codex|antigravity|opencode|codex-timeline>}
here=${0:A:h}
repo=${here:h:h}
root=/private/tmp/smalti-fx/$harness
local_dir=$here/recording.local/$harness
markers=$repo/scripts/observatory/markers.local
prompts=("Responde solo: hola fixture A" "Responde solo: hola fixture B")
ollama_pid=""

case $harness in
  codex) fixture=$repo/Packages/CodexHarnessAdapter/Tests/CodexHarnessAdapterTests/Fixtures/codex ;;
  codex-timeline) fixture=$repo/Packages/CodexHarnessAdapter/Tests/CodexHarnessAdapterTests/Fixtures/codex-timeline ;;
  antigravity) fixture=$repo/Packages/AntigravityHarnessAdapter/Tests/AntigravityHarnessAdapterTests/Fixtures/antigravity ;;
  opencode) fixture=$repo/Packages/OpenCodeHarnessAdapter/Tests/OpenCodeHarnessAdapterTests/Fixtures/opencode ;;
  claude) fixture=$repo/Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/claude ;;
  *) echo "unknown harness: $harness"; exit 2 ;;
esac
[[ -s $markers ]] || { echo "write your personal markers to $markers first"; exit 2; }

cleanup() {
  [[ -n $ollama_pid ]] && kill $ollama_pid 2>/dev/null || true
  pkill -f "$root/home" 2>/dev/null || true
}
trap cleanup EXIT

ollama_url() {
  if curl -s -m 2 http://127.0.0.1:11434/api/version >/dev/null; then
    echo http://127.0.0.1:11434
    return
  fi
  OLLAMA_HOST=127.0.0.1:11435 /opt/homebrew/bin/ollama serve >/dev/null 2>&1 &
  ollama_pid=$!
  for _ in {1..20}; do curl -s -m 1 http://127.0.0.1:11435/api/version >/dev/null && break; sleep 0.5; done
  echo http://127.0.0.1:11435
}

fresh_root() {
  rm -rf $root
  mkdir -p $root/home $root/work-a $root/work-b
  for work in $root/work-a $root/work-b; do git -C $work init -q; done
}

clean_env() {
  env -i HOME=$root/home USER=$USER PATH=/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin TERM=xterm-256color "$@"
}

record_codex() {
  codex_config
  local i=1
  for work in $root/work-a $root/work-b; do
    (cd $work && clean_env CODEX_HOME=$root/home/codex perl -e 'alarm 300; exec @ARGV' \
      codex exec -m qwen3:4b --skip-git-repo-check "${prompts[$i]}" >/dev/null)
    i=$((i + 1))
  done
}

codex_config() {
  local url=$(ollama_url)
  mkdir -p $root/home/codex
  # `ollama` is built in (127.0.0.1:11434) and cannot be redefined; another port needs a provider of its own.
  local provider=ollama
  if [[ $url != http://127.0.0.1:11434 ]]; then
    provider=smalti-ollama
    printf '[model_providers.smalti-ollama]\nname = "Ollama"\nbase_url = "%s/v1"\nwire_api = "responses"\n' \
      "$url" >$root/home/codex/providers.toml
  fi
  { printf 'model_provider = "%s"\nmodel = "qwen3:4b"\ncheck_for_update_on_startup = false\n' $provider
    [[ -f $root/home/codex/providers.toml ]] && cat $root/home/codex/providers.toml || true
  } >$root/home/codex/config.toml
  rm -f $root/home/codex/providers.toml
}

# F9: two turns of one session (exec, then exec resume) with tool calls, one of which fails.
record_codex-timeline() {
  codex_config
  printf 'uno\n' >$root/work-a/uno.txt
  printf 'dos\n' >$root/work-a/dos.txt
  (cd $root/work-a && clean_env CODEX_HOME=$root/home/codex perl -e 'alarm 300; exec @ARGV' \
    codex exec -m qwen3:4b --skip-git-repo-check "Run the shell command: ls" >/dev/null)
  (cd $root/work-a && clean_env CODEX_HOME=$root/home/codex perl -e 'alarm 300; exec @ARGV' \
    codex exec resume --last -m qwen3:4b --skip-git-repo-check "Run the shell command: cat missing.txt" >/dev/null)
}

record_opencode() {
  local url=$(ollama_url)
  mkdir -p $root/home/.config/opencode
  printf '{"provider":{"ollama":{"npm":"@ai-sdk/openai-compatible","name":"Ollama","options":{"baseURL":"%s/v1"},"models":{"qwen3:4b":{"name":"qwen3:4b"}}}},"model":"ollama/qwen3:4b","autoupdate":false}\n' \
    "$url" >$root/home/.config/opencode/opencode.json
  local i=1
  for work in $root/work-a $root/work-b; do
    (cd $work && clean_env XDG_DATA_HOME=$root/home/.local/share XDG_CONFIG_HOME=$root/home/.config \
      XDG_STATE_HOME=$root/home/.local/state XDG_CACHE_HOME=$root/home/.cache perl -e 'alarm 300; exec @ARGV' \
      opencode run --standalone "${prompts[$i]}" >/dev/null)
    i=$((i + 1))
  done
}

record_antigravity() {
  local login=$local_dir/login-home
  [[ -d $login ]] || { echo "put a logged-in Antigravity home in $login first"; exit 2; }
  ditto $login $root/home
  local i=1
  for work in $root/work-a $root/work-b; do
    (cd $work && clean_env perl -e 'alarm 180; exec @ARGV' agy -p "${prompts[$i]}" >/dev/null)
    i=$((i + 1))
    sleep 2
  done
}

record_claude() {
  local real=$repo/Packages/ClaudeTelemetryAdapter/Tests/ClaudeTelemetryAdapterTests/Fixtures/real/projects
  local projects=$root/home/.claude/projects
  for letter in a b; do
    local encoded=${${:-$root/work-$letter}//[\/.]/-}
    mkdir -p $projects/$encoded
    for file in $real/-fixture-work-$letter/*.jsonl; do
      sed "s|/fixture/work/$letter|$root/work-$letter|g; s|/fixture/home|$root/home|g" $file \
        >$projects/$encoded/${file:t}
    done
  done
  # A distinct first prompt per session, so the resume test sees the right one came back (review 1, M6).
  local -A markers=(401a63e1-c076-45fe-9f09-432da1c8cfa6 A 0259e0a5-46f8-44f8-bc38-edfa7d1a0f2b F
    7b1f7b2a-0c81-4aa0-8229-85de52add2e8 B)
  for transcript in $projects/*/*.jsonl; do
    local id=${transcript:t:r}
    [[ -n ${markers[$id]:-} ]] && python3 -I $here/mark_claude_prompt.py $transcript "fixture prompt ${markers[$id]}"
  done
}

fresh_root
record_$harness
rm -rf $local_dir/home
mkdir -p $local_dir
ditto $root/home $local_dir/home
python3 -I $here/sanitize_fixture.py $root/home $fixture/home --markers $markers
python3 -I $here/fixture_expectations.py $harness $root/home >$fixture/expected.json
case $harness in
  codex | codex-timeline) codex --version ;;
  antigravity) agy --version ;;
  opencode) opencode --version ;;
  claude) echo "transcripts 2.1.330 (F3)" ;;
esac >$fixture/VERSION
echo "fixture written to $fixture"
