#!/usr/bin/env bash
# T16: bundle the SPM executable into a proper macOS .app bundle.
#
#   Usage:  scripts/build-app.sh [version] [build]
#   Output: build/AerialWall.app
#
# Icon source: Assets/Icon.icon — Apple's Icon Composer format (macOS 26+).
# Compiled to Icon.icns by `actool`, exactly as Xcode 26 would.

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
cp "$BIN/AerialWall" "$APP/Contents/MacOS/AerialWall"
[ -f "$BIN/AerialWallAgent" ] && cp "$BIN/AerialWallAgent" "$APP/Contents/MacOS/AerialWallAgent"

# SPM bundles resources as AerialWall_AerialWall.bundle next to the executable
if [ -d "$BIN/AerialWall_AerialWall.bundle" ]; then
    echo "==> copy resource bundle"
    cp -R "$BIN/AerialWall_AerialWall.bundle" "$APP/Contents/Resources/"
fi

echo "==> copy pre-rendered icon assets"
# AerialWall.icon needs Xcode 26's actool to compile; CI's Xcode 16 can't.
# The icns + car are pre-rendered locally via scripts/regen-icon.sh and
# committed to Sources/AerialWall/Resources/ — copy those into the bundle.
ICON_SRC="$ROOT/Sources/AerialWall/Resources"
if [ ! -f "$ICON_SRC/AerialWall.icns" ] || [ ! -f "$ICON_SRC/AerialWall.car" ]; then
    echo "ERROR: pre-rendered icon assets missing. Run scripts/regen-icon.sh locally."
    exit 1
fi
cp "$ICON_SRC/AerialWall.icns" "$APP/Contents/Resources/AerialWall.icns"
cp "$ICON_SRC/AerialWall.car"  "$APP/Contents/Resources/Assets.car"

echo "==> Info.plist (version=$VERSION build=$BUILD)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    scripts/Info.plist.tpl > "$APP/Contents/Info.plist"
plutil -convert binary1 "$APP/Contents/Info.plist"

echo "==> verify"
plutil -lint "$APP/Contents/Info.plist"
codesign -dvv "$APP" 2>&1 | head -5 || true

echo
echo "Done: $APP"
echo "Test: open $APP"
