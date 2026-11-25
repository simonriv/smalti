#!/usr/bin/env bash
# F7.6: the issue forms the app opens exist and carry the field it fills (FeedbackReport.buildFieldID = "build").
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
forms="$root/.github/ISSUE_TEMPLATE"
total=5; n=0; failures=0
report() { n=$((n + 1)); if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"; else echo "[$n/$total] FAIL $1"; failures=$((failures + 1)); fi; }
field() { ruby -ryaml -e 'f = YAML.load_file(ARGV[0]); exit(f["body"].any? { |b| b["id"] == ARGV[1] } ? 0 : 1)' "$@" 2>/dev/null; }

field "$forms/bug.yml" build; report bug_form_has_build_field $?
field "$forms/idea.yml" build; report idea_form_has_build_field $?
ruby -ryaml -e 'exit(YAML.load_file(ARGV[0])["blank_issues_enabled"] == false ? 0 : 1)' "$forms/config.yml" 2>/dev/null; report blank_issues_disabled $?
grep -q 'buildFieldID = "build"' "$root/Packages/SmaltiCore/Sources/SmaltiCore/Domain/Support/FeedbackReport.swift"; report app_fills_the_same_field $?
grep -qx 'github: simonriv' "$root/.github/FUNDING.yml"; report funding_names_simonriv $?
exit $((failures > 0))
