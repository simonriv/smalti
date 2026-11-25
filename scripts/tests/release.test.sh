#!/usr/bin/env bash
# F7.6: the release scripts, end to end on local stand-ins (no network, no GitHub, throwaway keys).
# Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
rel="$root/scripts/release"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
total=27; n=0; failures=0
report() { n=$((n + 1)); if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"; else echo "[$n/$total] FAIL $1"; failures=$((failures + 1)); fi; }

# shellcheck source=/dev/null
source "$rel/lib.sh"
[[ "$(build_number 0.7.6)" == 706 && "$(build_number 1.12.3)" == 11203 && "$(build_number 0.10.0)" == 1000 ]]
report build_number_follows_the_formula $?

# Review 2 (M2): MINOR or PATCH of 100 or more would collide (0.7.100 = 0.8.0), so it is refused.
! build_number 0.7.100 > /dev/null 2>&1 && ! build_number 0.100.0 > /dev/null 2>&1
report build_number_refuses_components_of_100_or_more $?

# Review 2 (I1): prereleases would reach every user through the stable appcast; refused until there are channels.
out="$(SMALTI_VERSION=0.8.0-beta.1 "$rel/build.sh" v0.8.0-beta.1 "$work/out" 2>&1)"; status=$?
[[ $status != 0 && "$out" == *"prerelease"* ]]; report build_refuses_prereleases $?

# Review 2 (M1): bump-version.sh sets both versions in the project; a copy, never the real one.
mkdir -p "$work/bump/App/Smalti.xcodeproj" "$work/bump/scripts/release"
cp "$root/App/Smalti.xcodeproj/project.pbxproj" "$work/bump/App/Smalti.xcodeproj/"
cp "$rel/lib.sh" "$rel/bump-version.sh" "$work/bump/scripts/release/" 2>/dev/null
"$work/bump/scripts/release/bump-version.sh" 0.8.1 > /dev/null 2>&1
p="$work/bump/App/Smalti.xcodeproj/project.pbxproj"
[[ "$(grep -c 'MARKETING_VERSION = 0.8.1;' "$p")" -ge 2 && "$(grep -c 'CURRENT_PROJECT_VERSION = 801;' "$p")" -ge 2 \
  && "$(grep -c 'MARKETING_VERSION = ' "$p")" == "$(grep -c 'MARKETING_VERSION = 0.8.1;' "$p")" ]]
report bump_version_sets_marketing_and_build_number $?

[[ "$(version_of_tag v0.7.6)" == 0.7.6 ]] && ! version_of_tag 0.7.6 > /dev/null 2>&1 && ! version_of_tag v0.7 > /dev/null 2>&1
report tag_must_be_vX_Y_Z $?

out="$("$rel/build.sh" v9.9.9 "$work/out" 2>&1)"; status=$?
[[ $status != 0 && "$out" == *"does not match"* ]]; report build_refuses_a_tag_that_is_not_the_project_version $?

cat > "$work/expected-item.xml" <<'X'
    <item>
      <title>0.7.6</title>
      <pubDate>Wed, 25 Nov 2026 20:00:00 +0000</pubDate>
      <sparkle:version>706</sparkle:version>
      <sparkle:shortVersionString>0.7.6</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://smalti.sh/es/changelog#v0.7.6</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/simonriv/smalti/releases/download/v0.7.6/Smalti.dmg" length="18432000" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl" />
    </item>
X
"$rel/appcast-item.sh" 0.7.6 18432000 c2lnbmF0dXJl "Wed, 25 Nov 2026 20:00:00 +0000" > "$work/item.xml"
cmp -s "$work/item.xml" "$work/expected-item.xml"; report appcast_item_has_the_web_format $?

! "$rel/appcast-item.sh" 0.7.6 18432000 "" "Wed, 25 Nov 2026 20:00:00 +0000" > /dev/null 2>&1
report appcast_item_without_signature_is_refused $?

"$rel/cask.sh" 0.7.6 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > "$work/smalti.rb"
grep -q '^  version "0.7.6"$' "$work/smalti.rb" \
  && grep -q '^  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"$' "$work/smalti.rb" \
  && grep -q 'url "https://github.com/simonriv/smalti/releases/download/v#{version}/Smalti.dmg"' "$work/smalti.rb" \
  && grep -q '^  auto_updates true$' "$work/smalti.rb" && grep -q 'depends_on macos: :golden_gate$' "$work/smalti.rb" \
  && grep -q 'depends_on arch: :arm64' "$work/smalti.rb" && grep -q '"~/.config/smalti",' "$work/smalti.rb"
report cask_has_version_sha_and_the_spec_stanzas $?

! "$rel/cask.sh" 0.7.6 abc > /dev/null 2>&1; report cask_refuses_a_bad_sha256 $?

# The tap's workflow runs `brew style`; the same check here (Homebrew wants `macos: :golden_gate`, not ">= …").
mkdir -p "$work/style/Casks" && cp "$work/smalti.rb" "$work/style/Casks/smalti.rb"
(cd "$work/style" && HOMEBREW_NO_AUTO_UPDATE=1 brew style Casks/smalti.rb > /dev/null 2>&1); report cask_passes_brew_style $?

# Review 2 (M8): brew audit --cask --strict, offline, from a throwaway local tap (untapped right after).
git -C "$work/style" init -q && git -C "$work/style" add -A && git -C "$work/style" -c user.name=t -c user.email=t@localhost commit -qm c
# Homebrew 7 audits a third-party tap only once trusted (brew trust); the trust is withdrawn with the tap.
HOMEBREW_NO_AUTO_UPDATE=1 brew tap smaltitest/audit "$work/style" > /dev/null 2>&1 \
  && brew trust smaltitest/audit > /dev/null 2>&1 \
  && HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask --strict smaltitest/audit/smalti > "$work/audit.log" 2>&1
status=$?; brew untrust smaltitest/audit > /dev/null 2>&1; brew untap smaltitest/audit > /dev/null 2>&1
report cask_passes_brew_audit_strict $status

# A fake app, a DMG of it, and its contents.
mkdir -p "$work/app/Smalti.app/Contents/MacOS" && printf '#!/bin/sh\n' > "$work/app/Smalti.app/Contents/MacOS/Smalti"
"$rel/make-dmg.sh" "$work/app/Smalti.app" "$work/Smalti.dmg" > /dev/null 2>&1
mnt="$work/mnt"; mkdir -p "$mnt"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$work/Smalti.dmg" \
  && [[ -d "$mnt/Smalti.app" && -L "$mnt/Applications" && "$(readlink "$mnt/Applications")" == /Applications ]]
report dmg_holds_the_app_and_an_applications_link $?
hdiutil detach -quiet "$mnt" 2>/dev/null

# Throwaway EdDSA key: signing reads it from stdin and verifies against it.
key="$(openssl genpkey -algorithm ed25519 2>/dev/null | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64)"
SPARKLE_BIN="${SPARKLE_BIN:-$("$rel/fetch-sparkle-tools.sh" "$work/sparkle")}"; export SPARKLE_BIN
public="$(printf '%s' "$key" | "$rel/public-key.sh")"
signed="$(printf '%s' "$key" | "$rel/sign-update.sh" "$work/Smalti.dmg" "$public")"
[[ "$signed" =~ ^[A-Za-z0-9+/=]+\ [0-9]+$ && "${signed#* }" == "$(stat -f %z "$work/Smalti.dmg")" ]]
report signing_prints_signature_and_length $?

# Final review (I1): the system's LibreSSL cannot derive an Ed25519 public key; the script finds OpenSSL 3 itself.
[[ "$(printf '%s' "$key" | PATH=/usr/bin:/bin "$rel/public-key.sh" 2>/dev/null)" == "$public" ]]
report public_key_works_with_a_minimal_path $?

# Review 2 (I2): a key that is not the app's SUPublicEDKey stops the release before anything is published.
other="$(openssl genpkey -algorithm ed25519 2>/dev/null | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64)"
! printf '%s' "$other" | "$rel/sign-update.sh" "$work/Smalti.dmg" "$public" > /dev/null 2>&1
report signing_refuses_a_key_that_is_not_the_apps $?

# Local stand-ins for smalti-web and the tap.
git init -q --bare -b main "$work/web.git" && git init -q "$work/web" && mkdir -p "$work/web/public"
cp "$root/scripts/release/templates/appcast-empty.xml" "$work/web/public/appcast.xml"
git -C "$work/web" add -A && git -C "$work/web" -c user.name=t -c user.email=t@localhost commit -qm init \
  && git -C "$work/web" push -q "$work/web.git" HEAD:main 2>/dev/null
"$rel/push-appcast.sh" "$work/web.git" v0.7.6 "$work/item.xml" > /dev/null 2>&1
git clone -q -b release/v0.7.6 "$work/web.git" "$work/web-check" 2>/dev/null \
  && python3 - "$work/web-check/public/appcast.xml" <<'P'
import sys, xml.etree.ElementTree as ET
items = ET.parse(sys.argv[1]).getroot().find("channel").findall("item")
sys.exit(0 if items and items[0].findtext("title") == "0.7.6" else 1)
P
report appcast_branch_prepends_the_item $?

"$rel/push-appcast.sh" "$work/web.git" v0.7.7 "$work/item.xml" > /dev/null 2>&1 && git clone -q -b release/v0.7.7 "$work/web.git" "$work/web-check2" 2>/dev/null
[[ $? != 0 ]] || ! grep -q "<title>0.7.6</title>" "$work/web-check2/public/appcast.xml"
report appcast_item_must_match_the_tag $?

# Review 2 (I3): pushing the same branch again (a rerun) succeeds when nothing changed and fails when it did.
"$rel/push-appcast.sh" "$work/web.git" v0.7.6 "$work/item.xml" > /dev/null 2>&1; report rerun_with_the_same_item_succeeds $?
sed 's/length="18432000"/length="1"/' "$work/item.xml" > "$work/item-changed.xml"
! "$rel/push-appcast.sh" "$work/web.git" v0.7.6 "$work/item-changed.xml" > /dev/null 2>&1
report rerun_with_a_different_item_fails $?

# Final review (I2): once the appcast already lists the version (its PR merged), a rerun adds nothing.
git clone -q "$work/web.git" "$work/web-merge" 2>/dev/null && cd "$work/web-merge" \
  && sed -i '' "/prepends one <item>/r $work/item.xml" public/appcast.xml \
  && git -c user.name=t -c user.email=t@localhost commit -qam merged && git push -q origin HEAD:main 2>/dev/null; cd "$root"
"$rel/appcast-item.sh" 0.7.9 1 c2ln "Thu, 26 Nov 2026 10:00:00 +0000" | sed 's/0\.7\.9/0.7.6/g' > "$work/item-redo.xml"
"$rel/push-appcast.sh" "$work/web.git" v0.7.6 "$work/item-redo.xml" > /dev/null 2>&1 \
  && [[ "$(git --git-dir="$work/web.git" show main:public/appcast.xml | grep -c '<title>0.7.6</title>')" == 1 ]]
report rerun_after_merge_adds_nothing $?

# Review 2 (C1): with DEPLOY_KEY, both the clone and the push go through ssh with that key (a fake ssh in PATH
# records its arguments and runs the git command locally), and the key leaves no file behind.
mkdir -p "$work/sshbin" && cat > "$work/sshbin/ssh" <<'SSH'
#!/bin/sh
echo "$@" >> "$SSH_LOG"
for last; do :; done
exec sh -c "$last"
SSH
chmod +x "$work/sshbin/ssh"
sed 's/version "0.7.6"/version "0.7.8"/' "$work/smalti.rb" > "$work/smalti-078.rb"; mkdir -p "$work/tmp"
SSH_LOG="$work/ssh.log" PATH="$work/sshbin:$PATH" DEPLOY_KEY="fake-key" TMPDIR="$work/tmp" \
  "$rel/push-cask.sh" "github.local:$work/web.git" v0.7.8 "$work/smalti-078.rb" > /dev/null 2>&1
[[ "$(grep -c -- '-i ' "$work/ssh.log" 2>/dev/null)" -ge 2 ]] && git --git-dir="$work/web.git" rev-parse -q --verify release/v0.7.8 > /dev/null
report deploy_key_is_used_for_clone_and_push $?
[[ -d "$work/tmp" && -z "$(find "$work/tmp" -mindepth 1 2>/dev/null)" ]]; report deploy_key_leaves_no_file $?

git init -q --bare -b main "$work/tap.git" && git init -q "$work/tap" && printf '# tap\n' > "$work/tap/README.md"
git -C "$work/tap" add -A && git -C "$work/tap" -c user.name=t -c user.email=t@localhost commit -qm init \
  && git -C "$work/tap" push -q "$work/tap.git" HEAD:main 2>/dev/null
"$rel/push-cask.sh" "$work/tap.git" v0.7.6 "$work/smalti.rb" > /dev/null 2>&1
git clone -q -b release/v0.7.6 "$work/tap.git" "$work/tap-check" 2>/dev/null && cmp -s "$work/tap-check/Casks/smalti.rb" "$work/smalti.rb"
report cask_branch_holds_the_cask $?

# publish.sh: notes are required, and nothing reaches GitHub without them (fake gh records any call).
mkdir -p "$work/bin" && printf '#!/bin/sh\necho "$@" >> %q/gh.calls\n' "$work" > "$work/bin/gh" && chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH" "$rel/publish.sh" v9.9.9 "$work/Smalti.dmg" > /dev/null 2>&1; status=$?
[[ $status != 0 && ! -e "$work/gh.calls" ]]; report publish_needs_release_notes $?

grep -q 'if: ${{ !github.event.repository.private }}' "$root/.github/workflows/release.yml" \
  && grep -q 'runs-on: xcode-27' "$root/.github/workflows/release.yml"
report workflow_skips_private_repos_and_runs_on_xcode_27 $?

(cd "$root" && actionlint .github/workflows/*.yml > /dev/null 2>&1); report workflows_pass_actionlint $?

exit $((failures > 0))
