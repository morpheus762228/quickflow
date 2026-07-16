#!/bin/bash
# QuickFlow Build Script
# Compiles the Swift menu bar app and assembles a proper .app bundle
# with the Python backend bundled inside Resources.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/QuickFlow.app"

echo "⚡ Building QuickFlow..."

# Kill any running instance
pkill -f "QuickFlow.app/Contents/MacOS/QuickFlow" 2>/dev/null || true
sleep 0.3

# Assemble .app bundle structure
echo "📦 Assembling .app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Compile Swift source
echo "🔧 Compiling Swift..."
swiftc "$PROJECT_DIR/Sources/main.swift" \
    -o "$APP_DIR/Contents/MacOS/QuickFlow" \
    -framework Cocoa -framework AppKit -framework Carbon \
    -framework UserNotifications -framework AVFoundation -O

# Bundle the Python backend into Resources
echo "🐍 Bundling Python backend..."
cp -R "$PROJECT_DIR/backend/" "$APP_DIR/Contents/Resources/backend/"
cp "$PROJECT_DIR/requirements.txt" "$APP_DIR/Contents/Resources/"

echo ""
echo "✅ Build complete!"
echo "   App: $APP_DIR"
echo ""
echo "To install to /Applications:"
echo "   cp -R $APP_DIR /Applications/QuickFlow.app"
echo "   open /Applications/QuickFlow.app"
