#!/usr/bin/env bash
# Xcode build phase (F2): builds the `smalti` CLI (release, so hooks start fast) and copies it with the Claude Code
# plugin into the app's Resources: Contents/Resources/bin/smalti and Contents/Resources/claude-plugin/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="${TARGET_BUILD_DIR:?run from Xcode}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?run from Xcode}"
package="$root/Packages/IPCAdapter"
# A clean environment: Xcode's build settings would otherwise steer SwiftPM to the app's SDK and paths.
swiftpm() { /usr/bin/env -i PATH=/usr/bin:/bin HOME="$HOME" DEVELOPER_DIR="${DEVELOPER_DIR:-}" xcrun swift "$@"; }
swiftpm build -c release --package-path "$package" --product smalti --scratch-path "$package/.build-embed" > /dev/null
bin="$(swiftpm build -c release --package-path "$package" --scratch-path "$package/.build-embed" --show-bin-path)"
mkdir -p "$dest/bin"
cp "$bin/smalti" "$dest/bin/smalti"
rsync -a --delete "$root/App/ClaudePlugin/" "$dest/claude-plugin/"
