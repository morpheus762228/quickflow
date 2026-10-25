#!/bin/bash
# QuickFlow native build — compiles the Swift menu bar app, links whisper.cpp,
# and assembles a signed .app bundle (icon + model included).
#
#   ./build.sh              arm64 build for this Mac
#   ./build.sh --universal  arm64 + x86_64 (needs a second whisper.cpp build)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/QuickFlow.app"
BUILD_DIR="$PROJECT_DIR/build"
WHISPER_DIR="$PROJECT_DIR/vendor/whisper.cpp"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist" 2>/dev/null || echo 1.0.0)"
UNIVERSAL=0
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

echo "⚡ QuickFlow $VERSION"

# 1. whisper.cpp static libraries -------------------------------------------------
if [ ! -f "$WHISPER_DIR/build/src/libwhisper.a" ]; then
  echo "📥 Building whisper.cpp (one time, ~1 min)..."
  if [ ! -d "$WHISPER_DIR/.git" ]; then
    mkdir -p "$PROJECT_DIR/vendor"
    git clone --depth 1 --branch v1.7.6 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
  fi
  cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
    -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF >/dev/null
  cmake --build "$WHISPER_DIR/build" -j "$(sysctl -n hw.ncpu)" >/dev/null
fi

# 2. compile Swift ----------------------------------------------------------------
echo "🔧 Compiling Swift..."
mkdir -p "$BUILD_DIR"
SWIFT_FLAGS=(-parse-as-library -O -wmo
  -import-objc-header "$PROJECT_DIR/Sources/WhisperBridge.h"
  -I "$WHISPER_DIR/include" -I "$WHISPER_DIR/ggml/include")

LIBS=("$WHISPER_DIR/build/src/libwhisper.a"
  "$WHISPER_DIR/build/ggml/src/libggml.a"
  "$WHISPER_DIR/build/ggml/src/libggml-base.a"
  "$WHISPER_DIR/build/ggml/src/libggml-cpu.a"
  "$WHISPER_DIR/build/ggml/src/ggml-blas/libggml-blas.a"
  "$WHISPER_DIR/build/ggml/src/ggml-metal/libggml-metal.a")

LIBS_X86=("$WHISPER_DIR/build-x86/src/libwhisper.a"
  "$WHISPER_DIR/build-x86/ggml/src/libggml.a"
  "$WHISPER_DIR/build-x86/ggml/src/libggml-base.a"
  "$WHISPER_DIR/build-x86/ggml/src/libggml-cpu.a"
  "$WHISPER_DIR/build-x86/ggml/src/ggml-blas/libggml-blas.a"
  "$WHISPER_DIR/build-x86/ggml/src/ggml-metal/libggml-metal.a")

FRAMEWORKS=(-framework AppKit -framework Carbon -framework AVFoundation -framework CoreAudio
  -framework UserNotifications -framework Metal -framework MetalKit -framework Accelerate)

if [ "$UNIVERSAL" = 1 ]; then
  echo "🧱 Universal build (arm64 + x86_64)..."
  if [ ! -f "${LIBS_X86[0]}" ]; then
    echo "📥 Building whisper.cpp for Intel (one time)..."
    cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build-x86" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
      -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
      -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF >/dev/null
    cmake --build "$WHISPER_DIR/build-x86" -j "$(sysctl -n hw.ncpu)" >/dev/null
  fi
  swiftc "${SWIFT_FLAGS[@]}" -target arm64-apple-macos13.0 \
    "$PROJECT_DIR"/Sources/*.swift "${LIBS[@]}" "${FRAMEWORKS[@]}" -lc++ \
    -o "$BUILD_DIR/QuickFlow-arm64"
  swiftc "${SWIFT_FLAGS[@]}" -target x86_64-apple-macos13.0 \
    "$PROJECT_DIR"/Sources/*.swift "${LIBS_X86[@]}" "${FRAMEWORKS[@]}" -lc++ \
    -o "$BUILD_DIR/QuickFlow-x86_64"
  lipo -create "$BUILD_DIR/QuickFlow-arm64" "$BUILD_DIR/QuickFlow-x86_64" -output "$BUILD_DIR/QuickFlow"
else
  swiftc "${SWIFT_FLAGS[@]}" "$PROJECT_DIR"/Sources/*.swift "${LIBS[@]}" \
    "${FRAMEWORKS[@]}" -lc++ -o "$BUILD_DIR/QuickFlow"
fi

# 3. assemble bundle --------------------------------------------------------------
echo "📦 Assembling QuickFlow.app..."
if [ -d "$APP_DIR" ]; then rm -r "$APP_DIR"; fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/QuickFlow" "$APP_DIR/Contents/MacOS/QuickFlow"
cp "$PROJECT_DIR/assets/QuickFlow.icns" "$APP_DIR/Contents/Resources/QuickFlow.icns"

# Model: bundle it so first launch works offline. Override with QF_MODEL.
MODEL="${QF_MODEL:-}"
if [ -z "$MODEL" ]; then
  for candidate in ggml-small.en.bin ggml-base.en.bin ggml-large-v3-turbo.bin; do
    if [ -f "$PROJECT_DIR/models/$candidate" ]; then
      MODEL="$PROJECT_DIR/models/$candidate"
      break
    fi
  done
fi
if [ -n "$MODEL" ] && [ -f "$MODEL" ]; then
  mkdir -p "$APP_DIR/Contents/Resources/models"
  cp "$MODEL" "$APP_DIR/Contents/Resources/models/"
  echo "🧠 Bundled $(basename "$MODEL")"
else
  echo "⚠️  No model in models/ — app will ask for one on first launch."
fi

# 4. sign (ad-hoc keeps local runs working; Developer ID when available) ----------
IDENTITY="${QF_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  echo "🔏 Signing ad-hoc..."
  codesign --force --options runtime --entitlements "$PROJECT_DIR/QuickFlow.entitlements" \
    --sign - "$APP_DIR" 2>/dev/null
else
  echo "🔏 Signing with $IDENTITY..."
  codesign --force --options runtime --timestamp --entitlements "$PROJECT_DIR/QuickFlow.entitlements" \
    --sign "$IDENTITY" "$APP_DIR"
fi

echo ""
echo "✅ Built $APP_DIR"
echo "   Run: open $APP_DIR"
