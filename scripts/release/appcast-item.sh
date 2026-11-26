#!/usr/bin/env bash
# F7.6: the <item> smalti-web's docs/appcast.md asks for, on stdout.
#   appcast-item.sh <version> <dmg length> <EdDSA signature> [<RFC 2822 date>]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
version="${1:?version}"; length="${2:?length}"; signature="${3:-}"
date="${4:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"
# Tests only (scripts/release/test-update.sh): a local download and notes, so nothing leaves the machine.
download="${SMALTI_DOWNLOAD_URL:-https://github.com/$RELEASE_REPO/releases/download/v$version/$DMG_NAME}"
# F7.7: one link per language; Sparkle picks the one of the app's language (xml:lang, SUAppcast.m).
notes_en="${SMALTI_NOTES_URL:-https://smalti.sh/changelog#v$version}"
notes_es="${SMALTI_NOTES_URL:-https://smalti.sh/es/changelog#v$version}"
[[ -n "$signature" ]] || die "an appcast item without sparkle:edSignature is never published"
[[ "$length" =~ ^[0-9]+$ ]] || die "length must be a byte count: $length"
cat <<X
    <item>
      <title>$version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$(build_number "$version")</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink xml:lang="en">$notes_en</sparkle:releaseNotesLink>
      <sparkle:releaseNotesLink xml:lang="es">$notes_es</sparkle:releaseNotesLink>
      <enclosure url="$download" length="$length" type="application/octet-stream" sparkle:edSignature="$signature" />
    </item>
X
