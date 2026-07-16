# QuickFlow

A macOS menu bar app that turns your voice into text — anywhere, instantly.

Press **⌥⌘R** to start recording, speak, then press **⌥⌘T** to stop. QuickFlow transcribes your speech with Whisper and pastes the result directly into whatever app you're using.

## Features

- **🎙️ Voice-to-Text** — Whisper-powered transcription with automatic paste
- **🖥️ Context-Aware** — Detects the active app to adapt output style (email, code, message, note)
- **🧹 Smart Cleanup** — Rule-based filler word removal and punctuation fixing (optional LLM enhancement)
- **📚 Learns Over Time** — SQLite-backed correction store builds few-shot examples from your edits
- **⚡ System Utilities** — Quick actions for terminal, finder, screenshots, Wi-Fi, dark mode, clipboard
- **🔌 Zero External Services** — All local. No cloud API calls, no data leaves your machine.

## Requirements

- macOS 13.0+
- Xcode Command Line Tools (`xcode-select --install`)
- ffmpeg (`brew install ffmpeg`)
- Python 3.9+ with openai-whisper (`pip3 install --user openai-whisper`)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/jameslopez/quickflow.git
cd quickflow

# 2. Install dependencies
./setup.sh

# 3. Build the app
./build.sh

# 4. Install to /Applications
cp -R QuickFlow.app /Applications/

# 5. Launch
open /Applications/QuickFlow.app
```

On first launch, macOS will prompt for:
- **Microphone access** — required for recording
- **Accessibility** — required for auto-paste and context detection
- **Automation** — required for AppleScript interactions

Grant these in **System Settings → Privacy & Security**.

## Usage

| Shortcut | Action |
|----------|--------|
| **⌥⌘R** | Start recording |
| **⌥⌘T** | Stop & transcribe — text is pasted into the active app |

Click the ⚡ icon in the menu bar for quick actions: terminal, finder, screenshot, lock screen, Wi-Fi toggle, dark mode, and clipboard management.

## Architecture

```
QuickFlow.app/
├── Contents/
│   ├── MacOS/
│   │   └── QuickFlow          ← Swift menu bar app (native recording + hotkeys)
│   ├── Resources/
│   │   ├── backend/           ← Python transcription pipeline
│   │   │   ├── server.py      ← Orchestrator: ASR + context + cleanup + paste
│   │   │   ├── asr/           ← Whisper batch + streaming ASR with VAD
│   │   │   ├── llm/           ← Two-stage LLM pipeline (optional, rule-based fallback)
│   │   │   ├── context/       ← Screen context injection for accuracy
│   │   │   ├── learning/      ← Correction learning (SQLite)
│   │   │   └── budget.py     ← Latency budget with graceful degradation
│   │   └── requirements.txt
│   └── Info.plist
```

**Flow:** Swift app records audio natively (AVAudioRecorder) → hands off WAV to Python orchestrator → Whisper transcribes → rule-based cleaner removes filler words → context injector detects app style → text is copied to clipboard and pasted via AppleScript.

## Configuration

All config is via environment variables (set before launching the app):

| Variable | Default | Description |
|----------|---------|-------------|
| `QUICKFLOW_ASR_MODEL` | `small` | Whisper model size (tiny/base/small/medium/large) |
| `QUICKFLOW_LLM_MODEL` | _(empty)_ | Path to GGUF model for LLM-enhanced cleanup |
| `QUICKFLOW_STREAMING` | `0` | Enable streaming ASR (`1`) |
| `QUICKFLOW_BUDGET` | `normal` | Latency tier: `fast` / `normal` / `quality` |
| `QUICKFLOW_STYLE` | `auto` | Output style: `auto` / `default` / `email` / `note` / `code_comment` / `message` |
| `QUICKFLOW_MIC_INDEX` | _(auto)_ | Override ffmpeg avfoundation mic index |

## Optional: LLM-Enhanced Cleanup

For smarter transcript cleanup (beyond rule-based), install a local LLM:

```bash
pip3 install --user llama-cpp-python
```

Then set the model path:
```bash
export QUICKFLOW_LLM_MODEL=/path/to/model.gguf
```

## Optional: Streaming ASR

For lower-latency streaming transcription with VAD:

```bash
pip3 install --user faster-whisper sounddevice torch
export QUICKFLOW_STREAMING=1
```

## License

MIT
