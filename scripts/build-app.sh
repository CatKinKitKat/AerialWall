#!/usr/bin/env bash
# T16: bundle the SPM executable into a proper macOS .app bundle.
#
#   Usage:  scripts/build-app.sh [version] [build]
#   Output: build/AerialWall.app
#
# This script does NOT codesign or notarize — those require an Apple Developer
# certificate and Apple ID. See scripts/notarize.sh for that pass.

set -euo pipefail

VERSION="${1:-0.1.0-beta.1}"
BUILD="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)"

APP="build/AerialWall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "==> copy executable"
cp "$BIN/AerialWall"      "$APP/Contents/MacOS/AerialWall"
[ -f "$BIN/AerialWallAgent" ] && cp "$BIN/AerialWallAgent" "$APP/Contents/MacOS/AerialWallAgent"

# SPM bundles resources as AerialWall_AerialWall.bundle next to the executable
if [ -d "$BIN/AerialWall_AerialWall.bundle" ]; then
    echo "==> copy resource bundle"
    cp -R "$BIN/AerialWall_AerialWall.bundle" "$APP/Contents/Resources/"
fi

echo "==> compile AppIcon.icns from xcassets"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
ICONS_SRC="Sources/AerialWall/Resources/Assets.xcassets/AppIcon.appiconset"
# iconutil naming convention: icon_<size>x<size>[@2x].png
cp "$ICONS_SRC/icon_16.png"    "$ICONSET/icon_16x16.png"
cp "$ICONS_SRC/icon_16@2.png"  "$ICONSET/icon_16x16@2x.png"
cp "$ICONS_SRC/icon_32.png"    "$ICONSET/icon_32x32.png"
cp "$ICONS_SRC/icon_32@2.png"  "$ICONSET/icon_32x32@2x.png"
cp "$ICONS_SRC/icon_128.png"   "$ICONSET/icon_128x128.png"
cp "$ICONS_SRC/icon_128@2.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONS_SRC/icon_256.png"   "$ICONSET/icon_256x256.png"
cp "$ICONS_SRC/icon_256@2.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONS_SRC/icon_512.png"   "$ICONSET/icon_512x512.png"
cp "$ICONS_SRC/icon_512@2.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Info.plist (version=$VERSION build=$BUILD)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    scripts/Info.plist.tpl > "$APP/Contents/Info.plist"

echo "==> Info.plist.binary form (Finder prefers binary plist)"
plutil -convert binary1 "$APP/Contents/Info.plist"

echo "==> verify bundle"
plutil -lint "$APP/Contents/Info.plist"
codesign -dvv "$APP" 2>&1 | head -5 || echo "  (unsigned — run scripts/notarize.sh to sign+notarize)"

echo
echo "Done: $APP"
echo "Test: open $APP"
