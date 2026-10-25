#!/bin/bash
# Package QuickFlow.app into a distributable DMG.
#   ./package.sh            -> dist/QuickFlow-<version>.dmg
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/QuickFlow.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
DIST_DIR="$PROJECT_DIR/dist"
STAGE_DIR="$PROJECT_DIR/.dmg-stage"
DMG_PATH="$DIST_DIR/QuickFlow-$VERSION.dmg"

if [ ! -d "$APP_DIR" ]; then
  echo "❌ QuickFlow.app not found — run ./build.sh --universal first." >&2
  exit 1
fi

echo "💿 Packaging QuickFlow $VERSION..."
mkdir -p "$DIST_DIR"
if [ -d "$STAGE_DIR" ]; then rm -r "$STAGE_DIR"; fi
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/QuickFlow.app"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$STAGE_DIR/Read Me.txt" <<EOF
QuickFlow $VERSION — private, on-device dictation for macOS
============================================================

1. Drag QuickFlow into your Applications folder.

2. The first time you open it: right-click QuickFlow, choose Open, then Open
   again. QuickFlow is signed ad-hoc rather than notarized by Apple, so
   Gatekeeper asks once. On macOS 15 you may also need to allow it under
   System Settings > Privacy & Security.

   Terminal alternative:
     xattr -dr com.apple.quarantine /Applications/QuickFlow.app

3. Approve Microphone, and Accessibility so QuickFlow can paste for you.

Press Option-Command-R to start dictating, Option-Command-T to stop.
Escape cancels a take. The model is included; everything runs on this Mac.

Documentation: https://github.com/morpheus762228/quickflow
EOF

# Keep the DMG small: strip extended attributes that inflate the image.
xattr -cr "$STAGE_DIR/QuickFlow.app" 2>/dev/null || true

hdiutil create -volname "QuickFlow" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -r "$STAGE_DIR"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
printf '%s  %s\n' "$SHA" "$(basename "$DMG_PATH")" > "$DIST_DIR/SHA256SUMS"

echo ""
echo "✅ $DMG_PATH ($SIZE)"
echo "   sha256 $SHA"
echo "   checksum written to $DIST_DIR/SHA256SUMS"
