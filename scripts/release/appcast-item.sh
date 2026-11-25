#!/usr/bin/env bash
# F7.6: the <item> smalti-web's docs/appcast.md asks for, on stdout.
#   appcast-item.sh <version> <dmg length> <EdDSA signature> [<RFC 2822 date>]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
version="${1:?version}"; length="${2:?length}"; signature="${3:-}"
date="${4:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"
[[ -n "$signature" ]] || die "an appcast item without sparkle:edSignature is never published"
[[ "$length" =~ ^[0-9]+$ ]] || die "length must be a byte count: $length"
cat <<X
    <item>
      <title>$version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$(build_number "$version")</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://smalti.sh/changelog#v$version</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$RELEASE_REPO/releases/download/v$version/$DMG_NAME" length="$length" type="application/octet-stream" sparkle:edSignature="$signature" />
    </item>
X
