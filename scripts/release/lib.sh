#!/usr/bin/env bash
# F7.6: shared helpers of the release scripts (sourced).

die() { echo "error: $*" >&2; exit 1; }

# vX.Y.Z[-pre] -> X.Y.Z[-pre]; fails on anything else.
version_of_tag() {
  [[ "$1" =~ ^v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)$ ]] || { echo "tag must be vX.Y.Z: $1" >&2; return 1; }
  echo "${BASH_REMATCH[1]}"
}

# CFBundleVersion / sparkle:version: MAJOR*10000 + MINOR*100 + PATCH (a prerelease shares its release's number).
build_number() {
  local core="${1%%-*}" major minor patch
  IFS=. read -r major minor patch <<< "$core"
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

# Clones <git-url>'s default branch into a new temporary directory (printed). With DEPLOY_KEY set (the private
# key's text, from a secret), git uses it over SSH; the key lives in a 0600 file removed with the clone.
clone_satellite() {
  local url="$1" dir
  dir="$(mktemp -d)"
  if [[ -n "${DEPLOY_KEY:-}" ]]; then
    (umask 077; printf '%s\n' "$DEPLOY_KEY" > "$dir.key")
    export GIT_SSH_COMMAND="ssh -i $dir.key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  fi
  git clone -q --depth 1 --no-local "$url" "$dir/repo" || die "could not clone $url"
  echo "$dir"
}

# Commits everything in <repo> on a new branch and pushes it; the target repo's workflow opens the PR.
push_branch() {
  local repo="$1" branch="$2" message="$3"
  git -C "$repo" checkout -q -b "$branch"
  git -C "$repo" add -A
  git -C "$repo" -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit -qm "$message"
  git -C "$repo" push -q origin "$branch" || die "could not push $branch"
}
