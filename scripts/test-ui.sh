#!/usr/bin/env bash
# Runs only the XCUITests named (classes or single tests, any number; never the whole suite, testing rules:
# scripts/test-ui.sh MainWindowTests MenuTests/testAboutShowsVersionAndCommit), building once for all of it, and
# prints one line per finished test as "[n/total] ok|FAIL <Class.test>". Exits with xcodebuild's own status.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
logs="$root/build/test-ui"; mkdir -p "$logs"
args=(-project "$root/App/Smalti.xcodeproj" -scheme Smalti -destination "platform=macOS" -derivedDataPath "$root/build")
if [[ $# == 0 ]]; then
  echo "test-ui.sh: name the affected classes or tests (e.g. WelcomeTests HelpTests/testX); the whole e2e suite never runs" >&2
  exit 2
fi
only=(); for target in "$@"; do only+=("-only-testing:SmaltiUITests/$target"); done

xcodebuild build-for-testing "${args[@]}" > "$logs/build.log" 2>&1 || { tail -30 "$logs/build.log"; exit 1; }

rm -f "$logs/tests.json"
xcodebuild test-without-building "${args[@]}" ${only[@]+"${only[@]}"} -enumerate-tests -test-enumeration-style flat \
  -test-enumeration-format json -test-enumeration-output-path "$logs/tests.json" > "$logs/enumerate.log" 2>&1 \
  || { tail -30 "$logs/enumerate.log"; exit 1; }
total="$(python3 -I -c 'import json,sys
def count(node):
    if isinstance(node, dict):
        return sum(count(v) for k, v in node.items() if k != "disabledTests") + (1 if node.get("identifier","").count("/") == 2 else 0)
    if isinstance(node, list):
        return sum(count(v) for v in node)
    return 0
print(count(json.load(open(sys.argv[1]))))' "$logs/tests.json")"

xcodebuild test-without-building "${args[@]}" ${only[@]+"${only[@]}"} 2>&1 | tee "$logs/test.log" | awk -v total="$total" '
  /^Test Case .*(passed|failed)/ {
    n++
    match($0, /\[[^]]+\]/); name = substr($0, RSTART + 1, RLENGTH - 2)
    split(name, parts, " "); sub(/^.*\./, "", parts[1])
    status = ($0 ~ /passed/) ? "ok" : "FAIL"
    printf "[%d/%d] %s %s.%s\n", n, total, status, parts[1], parts[2]; fflush()
  }'
status="${PIPESTATUS[0]}"
[[ "$status" == 0 ]] || grep -E "error:|XCTAssert" "$logs/test.log" | head -20
exit "$status"
