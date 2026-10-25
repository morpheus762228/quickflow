#!/bin/bash
# Package QuickFlow.app into a distributable DMG.
#   ./package.sh            -> dist/QuickFlow-<version>.dmg
#
# With dmgbuild installed (pip install dmgbuild) the image gets the branded
# installer window from assets/dmg-background.png: app on the left, an
# Applications shortcut on the right, and a drag arrow between them.
# Without dmgbuild it falls back to a plain but still functional image.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/QuickFlow.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
DIST_DIR="$PROJECT_DIR/dist"
STAGE_DIR="$PROJECT_DIR/.dmg-stage"
DMG_PATH="$DIST_DIR/QuickFlow-$VERSION.dmg"
BACKGROUND="$PROJECT_DIR/assets/dmg-background.png"
VOLUME_ICON="$PROJECT_DIR/assets/QuickFlow.icns"

if [ ! -d "$APP_DIR" ]; then
  echo "❌ QuickFlow.app not found — run ./build.sh --universal first." >&2
  exit 1
fi

echo "💿 Packaging QuickFlow $VERSION..."
mkdir -p "$DIST_DIR"
if [ -d "$STAGE_DIR" ]; then rm -r "$STAGE_DIR"; fi
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/QuickFlow.app"

# Keep the image small: strip extended attributes that inflate it. This does
# not touch the code signature (that lives in Contents/_CodeSignature).
xattr -cr "$STAGE_DIR/QuickFlow.app" 2>/dev/null || true

DMGBUILD=()
if command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD=(dmgbuild)
elif python3 -c "import dmgbuild" >/dev/null 2>&1; then
  DMGBUILD=(python3 -m dmgbuild)
fi

if [ ${#DMGBUILD[@]} -gt 0 ] && [ -f "$BACKGROUND" ]; then
  "${DMGBUILD[@]}" -s "$PROJECT_DIR/Scripts/dmg_settings.py" \
    -D "stage=$STAGE_DIR" \
    -D "background=$BACKGROUND" \
    -D "volume_icon=$VOLUME_ICON" \
    "QuickFlow" "$DMG_PATH"
else
  echo "ℹ️  dmgbuild not found — building a plain image (pip install dmgbuild for the branded window)."
  ln -s /Applications "$STAGE_DIR/Applications"
  hdiutil create -volname "QuickFlow" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
fi

rm -r "$STAGE_DIR"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
printf '%s  %s\n' "$SHA" "$(basename "$DMG_PATH")" > "$DIST_DIR/SHA256SUMS"

echo ""
echo "✅ $DMG_PATH ($SIZE)"
echo "   sha256 $SHA"
echo "   checksum written to $DIST_DIR/SHA256SUMS"
