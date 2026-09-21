#!/usr/bin/env bash
#
# Builds AudioNinja/Assets.xcassets/AppIcon.appiconset from the master artwork in
# Support/AppIcon-Source-1024.png.
#
# iOS takes the 1024 image as-is and masks it itself. macOS has no such single-size mode and wants
# every size from 16 up, so they are resampled here rather than checked in by hand.
#
# Usage: scripts/generate-app-icon.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${REPO_ROOT}/Support/AppIcon-Source-1024.png"
DEST="${REPO_ROOT}/AudioNinja/Assets.xcassets/AppIcon.appiconset"

[ -f "${SOURCE}" ] || { echo "missing ${SOURCE}" >&2; exit 1; }

dimensions=$(sips -g pixelWidth -g pixelHeight "${SOURCE}" | awk '/pixel(Width|Height)/ {print $2}' | paste -sd x -)
[ "${dimensions}" = "1024x1024" ] || { echo "source must be 1024x1024, got ${dimensions}" >&2; exit 1; }

rm -rf "${DEST}"
mkdir -p "${DEST}"

cp "${SOURCE}" "${DEST}/icon-1024.png"

# macOS: point size and scale, so the pixel size is point x scale.
for entry in "16 1 16" "16 2 32" "32 1 32" "32 2 64" "128 1 128" "128 2 256" \
             "256 1 256" "256 2 512" "512 1 512" "512 2 1024"; do
    set -- ${entry}
    points=$1; scale=$2; pixels=$3
    suffix=""
    [ "${scale}" = "2" ] && suffix="@2x"
    sips -s format png -z "${pixels}" "${pixels}" "${SOURCE}" \
        --out "${DEST}/mac-${points}${suffix}.png" >/dev/null
done

cat > "${DEST}/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    { "filename" : "mac-16.png",     "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "mac-16@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "mac-32.png",     "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "mac-32@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "mac-128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "mac-128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "mac-256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "mac-256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "mac-512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "mac-512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "==> wrote $(ls "${DEST}"/*.png | wc -l | tr -d ' ') images to ${DEST#"${REPO_ROOT}/"}"
