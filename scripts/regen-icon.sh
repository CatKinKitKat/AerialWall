#!/usr/bin/env bash
# Regenerate Sources/AerialWall/Resources/Icon.icns from Assets/Icon.icon
# Run this whenever the Icon Composer source changes.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OUT=$(mktemp -d)
xcrun actool "$ROOT/AerialWall.icon" \
    --compile "$OUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AerialWall \
    --output-format human-readable-text \
    --output-partial-info-plist "$OUT/PartialInfo.plist" >/dev/null

cp "$OUT/AerialWall.icns" "$ROOT/Sources/AerialWall/Resources/AerialWall.icns"
# actool always emits the catalog as Assets.car regardless of --app-icon name
cp "$OUT/Assets.car"      "$ROOT/Sources/AerialWall/Resources/AerialWall.car"
rm -rf "$OUT"

echo "Regenerated:"
echo "  $ROOT/Sources/AerialWall/Resources/AerialWall.icns (legacy, single appearance)"
echo "  $ROOT/Sources/AerialWall/Resources/AerialWall.car  (light + dark + tinted)"
