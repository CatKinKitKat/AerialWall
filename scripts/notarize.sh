#!/usr/bin/env bash
# T16: codesign + notarize an AerialWall.app bundle and package it into a DMG.
#
#   Required environment variables:
#     APPLE_DEVELOPER_ID    Developer ID Application certificate Common Name
#                           e.g. "Developer ID Application: Jane Doe (TEAMID)"
#     APPLE_ID              Apple ID email
#     APPLE_TEAM_ID         Team ID (10 chars)
#     APPLE_APP_PASSWORD    App-specific password from appleid.apple.com
#
#   Usage:  scripts/notarize.sh [version]
#   Output: build/AerialWall-<version>.dmg

set -euo pipefail

VERSION="${1:-0.1.0-beta.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/AerialWall.app"
DMG="build/AerialWall-$VERSION.dmg"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found. Run scripts/build-app.sh first."
    exit 1
fi

: "${APPLE_DEVELOPER_ID:?APPLE_DEVELOPER_ID must be set}"
: "${APPLE_ID:?APPLE_ID must be set}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID must be set}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD must be set}"

echo "==> codesign (hardened runtime, deep)"
codesign --force --options runtime --timestamp --deep \
    --sign "$APPLE_DEVELOPER_ID" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> zip for notarization"
ZIP="build/AerialWall-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> notarytool submit"
xcrun notarytool submit "$ZIP" \
    --apple-id    "$APPLE_ID" \
    --team-id     "$APPLE_TEAM_ID" \
    --password    "$APPLE_APP_PASSWORD" \
    --wait

echo "==> staple"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> build DMG"
rm -f "$DMG"
hdiutil create -volname "AerialWall" \
    -srcfolder "$APP" \
    -ov -format UDZO \
    "$DMG"

echo "==> codesign DMG"
codesign --force --sign "$APPLE_DEVELOPER_ID" --timestamp "$DMG"

echo "==> notarize DMG"
xcrun notarytool submit "$DMG" \
    --apple-id    "$APPLE_ID" \
    --team-id     "$APPLE_TEAM_ID" \
    --password    "$APPLE_APP_PASSWORD" \
    --wait
xcrun stapler staple "$DMG"

rm -f "$ZIP"

echo
echo "Done: $DMG"
echo "Verify: spctl -a -t open --context context:primary-signature -v $DMG"
