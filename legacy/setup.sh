#!/bin/bash
# QuickFlow Setup Script
# Installs Python dependencies needed for the transcription backend.
# Run this once before launching QuickFlow.
set -e

echo "⚡ QuickFlow Setup"
echo "=================="
echo ""

# Check macOS version
if ! sw_vers -productVersion | grep -qE '^1[3-9]\.|^2[0-9]\.'; then
    echo "⚠️  QuickFlow requires macOS 13.0 or later."
    sw_vers -productVersion
    exit 1
fi
echo "✅ macOS $(sw_vers -productVersion)"

# Check for Xcode Command Line Tools (needed for Swift compilation)
if ! xcode-select -p &>/dev/null; then
    echo "📦 Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    echo "⏳ Please wait for the installation to complete, then re-run this script."
    exit 0
fi
echo "✅ Xcode Command Line Tools installed"

# Check for ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    echo "📦 Installing ffmpeg..."
    if command -v brew &>/dev/null; then
        brew install ffmpeg
    else
        echo "⚠️  ffmpeg is required. Install Homebrew (https://brew.sh) then run: brew install ffmpeg"
        exit 1
    fi
fi
echo "✅ ffmpeg $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
PIP_OK=0

# Try pip3 directly
if pip3 install --user openai-whisper 2>/dev/null; then
    PIP_OK=1
else
    # Try with python3 -m pip
    if python3 -m pip install --user openai-whisper 2>/dev/null; then
        PIP_OK=1
    fi
fi

if [ "$PIP_OK" -eq 1 ]; then
    echo "✅ openai-whisper installed"
else
    echo "⚠️  Could not install openai-whisper automatically."
    echo "   Please run manually: pip3 install --user openai-whisper"
    exit 1
fi

# Verify whisper CLI is accessible
WHISPER_FOUND=""
if command -v whisper &>/dev/null; then
    WHISPER_FOUND="whisper"
else
    for py_ver in 3.9 3.10 3.11 3.12 3.13; do
        candidate="$HOME/Library/Python/${py_ver}/bin/whisper"
        if [ -f "$candidate" ]; then
            WHISPER_FOUND="$candidate"
            break
        fi
    done
fi

if [ -n "$WHISPER_FOUND" ]; then
    echo "✅ whisper CLI found: $WHISPER_FOUND"
else
    echo "⚠️  whisper CLI not found in PATH. It may need to be added:"
    echo "   export PATH=\"\$HOME/Library/Python/3.9/bin:\$PATH\""
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "   1. Build the app:    ./build.sh"
echo "   2. Install it:       cp -R QuickFlow.app /Applications/"
echo "   3. Launch:          open /Applications/QuickFlow.app"
echo "   4. Grant permissions: System Settings → Privacy → Microphone + Accessibility"
echo ""
echo "Shortcuts:"
echo "   ⌥⌘R — Start Recording"
echo "   ⌥⌘T — Stop & Transcribe"
