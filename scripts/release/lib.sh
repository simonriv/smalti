#!/usr/bin/env bash
# F7.6: shared helpers of the release scripts (sourced).

die() { echo "error: $*" >&2; exit 1; }

# vX.Y.Z[-pre] -> X.Y.Z[-pre]; fails on anything else.
version_of_tag() {
  [[ "$1" =~ ^v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)$ ]] || { echo "tag must be vX.Y.Z: $1" >&2; return 1; }
  echo "${BASH_REMATCH[1]}"
}

# CFBundleVersion / sparkle:version: MAJOR*10000 + MINOR*100 + PATCH (a prerelease shares its release's number).
# MINOR and PATCH must stay below 100, or two versions would share a number (0.7.100 = 0.8.0).
build_number() {
  local core="${1%%-*}" major minor patch
  IFS=. read -r major minor patch <<< "$core"
  (( 10#$minor < 100 && 10#$patch < 100 )) || { echo "MINOR and PATCH must be below 100: $1" >&2; return 1; }
  echo $((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
}

# MARKETING_VERSION of the app target (every configuration carries the same one).
project_version() {
  local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$root/App/Smalti.xcodeproj/project.pbxproj" | sort -u | head -1
}

readonly RELEASE_REPO="simonriv/smalti"
readonly DMG_NAME="Smalti.dmg"
readonly MINIMUM_SYSTEM_VERSION="27.0"

# clone_satellite <git url> <dir>: clones the default branch into <dir>/repo. With DEPLOY_KEY set (the private
# key's text, from a secret), git reaches the remote over SSH with that key, for the clone and for every later push
# (core.sshCommand); the key lives in <dir>/key (0600), so the caller's trap that removes <dir> removes it too. Not
# meant to run in a subshell: nothing it sets must be lost before the push.
clone_satellite() {
  local url="$1" dir="$2" ssh=()
  if [[ -n "${DEPLOY_KEY:-}" ]]; then
    (umask 077; printf '%s\n' "$DEPLOY_KEY" > "$dir/key")
    ssh=(-c "core.sshCommand=ssh -i $dir/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$(dirname "${BASH_SOURCE[0]}")/github-known-hosts")
  fi
  git ${ssh[@]+"${ssh[@]}"} clone -q --depth 1 --no-local "$url" "$dir/repo" || die "could not clone $url"
  if [[ -n "${DEPLOY_KEY:-}" ]]; then git -C "$dir/repo" config core.sshCommand "${ssh[1]#core.sshCommand=}"; fi
}

# Commits everything in <repo> on a new branch and pushes it; the target repo's workflow opens the PR. A rerun
# whose branch already holds the same files succeeds; one with different files fails instead of overwriting.
push_branch() {
  local repo="$1" branch="$2" message="$3"
  git -C "$repo" checkout -q -b "$branch"
  git -C "$repo" add -A
  git -C "$repo" -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit -qm "$message"
  if git -C "$repo" fetch -q --depth 1 origin "$branch" 2> /dev/null; then
    [[ "$(git -C "$repo" rev-parse FETCH_HEAD^{tree})" == "$(git -C "$repo" rev-parse HEAD^{tree})" ]] \
      && { echo "$branch already holds these files" >&2; return 0; }
    die "$branch already exists with other files; delete it or use a new version"
  fi
  git -C "$repo" push -q origin "$branch" || die "could not push $branch"
}
