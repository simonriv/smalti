#!/usr/bin/env bash
# F7.6: THIRD_PARTY_NOTICES.md names every component the binary carries. Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
check="$root/scripts/release/check-notices.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
total=6; n=0; failures=0

report() { # case status(0 ok)
  n=$((n + 1))
  if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"; else echo "[$n/$total] FAIL $1"; failures=$((failures + 1)); fi
}

# A binary with two of the probed components (sentry and breakpad) and nothing else.
printf 'void sentry_init(void){}\nvoid sentry__breakpad_backend_startup(void){}\nint main(void){return 0;}\n' > "$work/fake.c"
clang -o "$work/fake" "$work/fake.c" 2>/dev/null

"$check" "$root/THIRD_PARTY_NOTICES.md" > /dev/null 2>&1; report repository_notices_are_complete $?
"$check" "$root/THIRD_PARTY_NOTICES.md" "$work/fake" > /dev/null 2>&1; report probed_binary_is_covered $?

grep -v "^| sentry-native |" "$root/THIRD_PARTY_NOTICES.md" > "$work/no-row.md"
out="$("$check" "$work/no-row.md" "$work/fake" 2>&1)"; status=$?
[[ $status != 0 && "$out" == *"sentry-native"* ]]; report missing_row_of_a_linked_component_fails $?

sed 's/^## Breakpad$/## Otro/' "$root/THIRD_PARTY_NOTICES.md" > "$work/no-section.md"
out="$("$check" "$work/no-section.md" "$work/fake" 2>&1)"; status=$?
[[ $status != 0 && "$out" == *"Breakpad"* ]]; report missing_section_of_a_linked_component_fails $?

sed 's/^## Sparkle$/## Otro/' "$root/THIRD_PARTY_NOTICES.md" > "$work/no-sparkle.md"
"$check" "$work/no-sparkle.md" > /dev/null 2>&1; [[ $? != 0 ]]; report always_required_component_missing_fails $?

"$check" "$work/absent.md" > /dev/null 2>&1; [[ $? != 0 ]]; report missing_file_fails $?

exit $((failures > 0))
