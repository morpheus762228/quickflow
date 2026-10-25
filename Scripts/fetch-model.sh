#!/bin/bash
# Download a whisper.cpp model into models/ so build.sh can bundle it.
#
#   ./Scripts/fetch-model.sh                 # small.en (the bundled default)
#   ./Scripts/fetch-model.sh base.en         # smaller, faster, less accurate
#   ./Scripts/fetch-model.sh large-v3-turbo  # best accuracy, 1.5 GB
#
# Set QF_MODEL_DEST to download somewhere other than ./models.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${QF_MODEL_DEST:-$PROJECT_DIR/models}"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
NAME="${1:-small.en}"

case "$NAME" in
  *.bin) FILE="$NAME" ;;
  *)     FILE="ggml-$NAME.bin" ;;
esac

mkdir -p "$DEST"
TARGET="$DEST/$FILE"

if [ -f "$TARGET" ]; then
  echo "✅ Already present: $TARGET"
  echo "   $(du -h "$TARGET" | cut -f1)"
  exit 0
fi

echo "⬇️  $FILE"
echo "   from $BASE_URL/$FILE"
echo "   into $TARGET"

# Download to a .part file so an interrupted transfer never looks like a model.
curl --fail --location --progress-bar --output "$TARGET.part" "$BASE_URL/$FILE"
mv "$TARGET.part" "$TARGET"

BYTES="$(stat -f%z "$TARGET")"
if [ "$BYTES" -lt 20000000 ]; then
  echo "❌ $FILE is only $BYTES bytes — that looks like an error page, not a model." >&2
  echo "   Check the name (try: tiny.en, base.en, small.en, medium.en, large-v3-turbo)." >&2
  exit 1
fi

echo ""
echo "✅ $TARGET ($(du -h "$TARGET" | cut -f1))"
echo "   sha256 $(shasum -a 256 "$TARGET" | cut -d' ' -f1)"
echo ""
echo "Next: ./build.sh --universal   (bundles this model into QuickFlow.app)"
