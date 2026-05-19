#!/usr/bin/env bash
# Regenerate Sources/AerialWall/Resources/Icon.icns from Assets/Icon.icon
# Run this whenever the Icon Composer source changes.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OUT=$(mktemp -d)
xcrun actool "$ROOT/Assets/Icon.icon" \
    --compile "$OUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon Icon \
    --output-format human-readable-text \
    --output-partial-info-plist "$OUT/PartialInfo.plist" >/dev/null

cp "$OUT/Icon.icns"   "$ROOT/Sources/AerialWall/Resources/Icon.icns"
cp "$OUT/Assets.car"  "$ROOT/Sources/AerialWall/Resources/Assets.car"
rm -rf "$OUT"

echo "Regenerated:"
echo "  $ROOT/Sources/AerialWall/Resources/Icon.icns   (legacy, single appearance)"
echo "  $ROOT/Sources/AerialWall/Resources/Assets.car  (light + dark + tinted)"
