#!/bin/bash
# Install the helper behind the Debug-only "Open YouTube URL…" command (macOS).
#
# NSUserUnixTask only runs scripts from the app's Application Scripts folder, and the sandboxed
# app cannot write there itself, so this copies scripts/youtube-audio.sh into it. Run it again
# after changing that script.
set -euo pipefail

BUNDLE_ID="com.simplepatrick.AudioNinja"
DEST="$HOME/Library/Application Scripts/$BUNDLE_ID"
SRC="$(cd "$(dirname "$0")" && pwd)/youtube-audio.sh"

mkdir -p "$DEST"
cp "$SRC" "$DEST/youtube-audio.sh"
chmod 755 "$DEST/youtube-audio.sh"
echo "Installed $DEST/youtube-audio.sh"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
missing=()
command -v yt-dlp >/dev/null || missing+=(yt-dlp)
command -v ffmpeg >/dev/null || missing+=(ffmpeg)
if [ ${#missing[@]} -gt 0 ]; then
    echo "Still needed: brew install ${missing[*]}"
fi
