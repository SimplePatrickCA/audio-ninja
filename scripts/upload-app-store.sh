#!/usr/bin/env bash
#
# Archives Audio Ninja and uploads it to App Store Connect for TestFlight.
#
# Every upload needs a build number higher than the last one for its platform. Bump
# CURRENT_PROJECT_VERSION in scripts/generate-xcodeproj.py, regenerate the project, and commit
# before running this. Signing and upload use the Apple account signed in to Xcode.
#
# Usage: scripts/upload-app-store.sh [iOS] [macOS]     (both when no platform is given)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="build/app-store"
EXPORT_OPTIONS="Support/ExportOptions-AppStore.plist"

platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(iOS macOS)

build_number=$(xcodebuild -project AudioNinja.xcodeproj -scheme AudioNinja -configuration Release \
    -showBuildSettings 2>/dev/null | awk '$1 == "CURRENT_PROJECT_VERSION" { print $3; exit }')
echo "==> uploading build ${build_number} for: ${platforms[*]}"

# The logic tests are the cheapest thing that can stop a bad build reaching testers.
swift test --package-path Packages/AudioNinjaKit

for platform in "${platforms[@]}"; do
    archive="${BUILD_DIR}/AudioNinja-${platform}.xcarchive"
    rm -rf "${archive}" "${BUILD_DIR}/export-${platform}"

    echo "==> archiving ${platform}"
    xcodebuild archive \
        -project AudioNinja.xcodeproj -scheme AudioNinja -configuration Release \
        -destination "generic/platform=${platform}" \
        -archivePath "${archive}" \
        -allowProvisioningUpdates

    echo "==> uploading ${platform}"
    xcodebuild -exportArchive \
        -archivePath "${archive}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        -exportPath "${BUILD_DIR}/export-${platform}" \
        -allowProvisioningUpdates
done

echo "==> uploaded build ${build_number}. App Store Connect emails when processing finishes."
