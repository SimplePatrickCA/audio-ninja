#!/bin/bash
# Download the audio of a YouTube video for Audio Ninja's Debug-only "Open YouTube URL…" command.
#
#   youtube-audio.sh <url> <m4a|mp3|wav> <output-dir>
#
# Prints the downloaded file's path on stdout, and yt-dlp's progress on stderr.
#
# The sandboxed app cannot run yt-dlp itself: a child process inherits the sandbox, so it could
# neither read Homebrew's files nor reach the network. NSUserUnixTask runs a script from
# ~/Library/Application Scripts/<bundle id>/ outside the sandbox, which is why this is a separate
# script, installed there by scripts/install-youtube-helper.sh.
set -euo pipefail

# NSUserUnixTask starts with a minimal environment, without Homebrew on PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ $# -ne 3 ]; then
    echo "usage: $(basename "$0") <url> <m4a|mp3|wav> <output-dir>" >&2
    exit 64
fi
url=$1
format=$2
outdir=$3

if ! command -v yt-dlp >/dev/null; then
    echo "yt-dlp is not installed. Run: brew install yt-dlp ffmpeg" >&2
    exit 69
fi

case "$format" in
    m4a)
        # YouTube's AAC stream, saved as is. No re-encode, so no generation loss. ffmpeg is used
        # only to tidy the container if it is present.
        selection=(-f 'bestaudio[ext=m4a]/bestaudio')
        ;;
    mp3|wav)
        if ! command -v ffmpeg >/dev/null; then
            echo "ffmpeg is needed for $format. Run: brew install ffmpeg" >&2
            exit 69
        fi
        selection=(-f bestaudio -x --audio-format "$format" --audio-quality 0)
        ;;
    *)
        echo "unknown format '$format': use m4a, mp3 or wav" >&2
        exit 64
        ;;
esac

mkdir -p "$outdir"

# yt-dlp writes its progress to stdout, so all of its output goes to stderr and the final path
# reaches stdout through a file instead. --newline makes each progress update a whole line the
# app can show.
pathfile=$(mktemp -t youtube-audio)
trap 'rm -f "$pathfile"' EXIT

yt-dlp "${selection[@]}" \
    --no-playlist \
    --newline --progress-delta 0.5 \
    --print-to-file after_move:filepath "$pathfile" \
    -o "$outdir/%(title).150B [%(id)s].%(ext)s" \
    -- "$url" >&2

cat "$pathfile"
