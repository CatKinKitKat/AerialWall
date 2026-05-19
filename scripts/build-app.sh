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

echo "==> actool: compile AerialWall.icon → AerialWall.icns + Assets.car"
ACTOOL_OUT=$(mktemp -d)
xcrun actool "$ROOT/AerialWall.icon" \
    --compile "$ACTOOL_OUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AerialWall \
    --output-format human-readable-text \
    --output-partial-info-plist "$ACTOOL_OUT/PartialInfo.plist" >/dev/null
cp "$ACTOOL_OUT/AerialWall.icns" "$APP/Contents/Resources/AerialWall.icns"
# Assets.car carries the multi-appearance renditions (light/dark/tinted)
[ -f "$ACTOOL_OUT/Assets.car" ] && cp "$ACTOOL_OUT/Assets.car" "$APP/Contents/Resources/"
rm -rf "$ACTOOL_OUT"

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
