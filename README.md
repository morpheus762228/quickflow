# QuickFlow

**Private, on-device dictation for macOS.** Press ⌥⌘R, talk, press ⌥⌘T. Clean, formatted text lands in whatever app you were using — usually in under a second. No account, no cloud, no audio ever leaving your Mac.

Native Swift + [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) with the Metal backend. No Python, no Electron, no background server, no telemetry.

![The QuickFlow panel while dictating, with live subtitles](docs/images/live-subtitles.png)

## Why this exists

Built-in dictation is fine for a sentence. It is not built for a paragraph you have to think about: you cannot see what it heard, you cannot feed it your project's vocabulary, and you cannot get the text back once it lands wrong.

QuickFlow is built around three things:

- **You can see it working.** The floating panel shows a level meter while you talk and, optionally, the transcript as it grows — so a two-minute take is never a black box.
- **The text is ready to send.** Filler words and stutters are removed, spoken punctuation is applied, and spacing adapts to whether you are writing an email, chat, prose, or code.
- **It stays on your Mac.** The model runs locally, the audio is transcribed in memory, and the app contains no networking code.

## Install

**The easiest way is Homebrew — no Gatekeeper dialog at all:**

```bash
brew tap morpheus762228/quickflow
brew trust morpheus762228/quickflow   # Homebrew 6 asks you to trust third-party taps
brew install --cask quickflow
```

The cask verifies the checksum, installs into `/Applications`, and clears the
quarantine attribute, so the first double-click just works. (Requires
Homebrew 6+.)

**Or one file, one drag.** Download **`QuickFlow-3.0.dmg`** (about 450 MB — the model is inside) from [Releases](https://github.com/morpheus762228/quickflow/releases), open it, and drag **QuickFlow** onto **Applications**.

Then three things, once:

1. **First launch** — macOS blocks the first double-click, because the app is signed ad-hoc rather than notarized. In the **"QuickFlow" Not Opened** dialog click **Done** (never *Move to Trash*), then open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway** next to *"QuickFlow" was blocked to protect your Mac*, authenticate, and double-click QuickFlow again — the second dialog also has an **Open Anyway** button. On macOS 14 and earlier, right-click → **Open** → **Open** works instead. One time only; a plain double-click works afterwards.
2. **Microphone** — required; nothing can be transcribed without it.
3. **Accessibility** — lets QuickFlow paste into the frontmost app. Without it the transcript still lands on your clipboard.

Step-by-step, including the Gatekeeper fallbacks and how to check the checksum: **[docs/INSTALL.md](docs/INSTALL.md)**.

> The repository is private for now, so the Releases page asks you to be signed in to GitHub. `gh release download v3.0.0 --repo morpheus762228/quickflow --pattern 'QuickFlow-3.0.dmg'` works too.

Prefer the terminal?

```bash
curl -L -o /tmp/QuickFlow.dmg \
  https://github.com/morpheus762228/quickflow/releases/download/v3.0.0/QuickFlow-3.0.dmg
hdiutil attach /tmp/QuickFlow.dmg -nobrowse
cp -R /Volumes/QuickFlow/QuickFlow.app /Applications/
xattr -dr com.apple.quarantine /Applications/QuickFlow.app
hdiutil detach /Volumes/QuickFlow
open /Applications/QuickFlow.app
```

(The `curl` line needs the repository to be public, or a GitHub token: `-H "Authorization: token $GH_TOKEN"`.)

**Requirements:** macOS 13 Ventura or later, Apple Silicon or Intel, about 1 GB of free disk space. Intel Macs work but transcribe at roughly real time instead of 20–30× real time.

## Use

| Shortcut | Action |
| --- | --- |
| **⌥⌘R** | Start dictating |
| **⌥⌘T** | Stop, transcribe, paste |
| **Esc** | Throw the take away without transcribing |

Click the menu bar icon for **Start / Finish**, **Copy Last Transcript**, **Recent Transcripts**, **Live Subtitles**, **Settings**, and **About**.

Speak naturally. Say "period", "comma", "question mark", "new paragraph" and they become punctuation. "Um", "uh", and repeated words are dropped. Greetings and sign-offs in an email get paragraph breaks; code keeps its casing.

![First-run window](docs/images/welcome.png)

### Live subtitles

Turn on **Live Subtitles** (on by default) and the panel shows what whisper heard while you are still talking, growing to four lines and keeping the newest words in view. It re-decodes roughly the last twelve seconds about twice a second, so text settles quickly and never double-prints.

The text you paste is **not** the preview. When you stop, QuickFlow throws the preview away and runs one clean decode over the entire take, so a half-finished word can appear on screen but never in your document.

### Settings

| Setting | What it does |
| --- | --- |
| Input | Microphone picker. Virtual devices (BlackHole, Loopback) are skipped when a real mic exists. |
| Model | Any `ggml-*.bin` in `~/Library/Application Support/QuickFlow/models`. |
| Language | `en`, `auto`, or a specific language code. |
| Custom vocabulary | Names, acronyms, and jargon passed to the model as a prompt. This is the single biggest accuracy win for real work. |
| Paste automatically | Off means transcripts only go to the clipboard. |
| Keep my clipboard | Restores what you had copied before dictating. |
| Smart formatting | Filler removal, capitalisation, spoken punctuation, per-app spacing. |
| Sound cues | Short tone on start and stop. |
| Launch at login | Keeps QuickFlow ready in the menu bar. |

## Performance

Measured on an M-series Mac with the bundled `small.en` model:

```
Ready in 0.59s · 12.9s audio in 0.44s (29.1× realtime)
```

The model is loaded and warmed up at launch, so the first dictation does not pay a Metal shader compilation cost. Recording is 16 kHz mono, capped at five minutes per take, and transcribed from memory — audio is never written to disk by the app.

## Command line

The same binary is also a CLI, which makes batch transcription and benchmarking easy:

```bash
QuickFlow.app/Contents/MacOS/QuickFlow --help
QuickFlow.app/Contents/MacOS/QuickFlow --check
QuickFlow.app/Contents/MacOS/QuickFlow --devices
QuickFlow.app/Contents/MacOS/QuickFlow --transcribe talk.wav --clean --style email
QuickFlow.app/Contents/MacOS/QuickFlow --dictate
```

`--transcribe` writes text to stdout and timing to stderr. `--check` prints permission status, available models, and input devices — the fastest way to diagnose "nothing happened".

## Models

| Model | Size | Notes |
| --- | --- | --- |
| `ggml-small.en` | 465 MB | **Bundled.** Best balance of accuracy and speed. |
| `ggml-base.en` | 141 MB | Faster and lighter; more mistakes on names. |
| `ggml-large-v3-turbo` | 1.5 GB | Most accurate; wants RAM and a recent Mac. |

Drop any `ggml-*.bin` from [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp) into `~/Library/Application Support/QuickFlow/models/` and pick it in Settings. The app prefers `large-v3-turbo`, then `small.en`, then `base.en` when more than one is installed.

## Build from source

```bash
git clone https://github.com/morpheus762228/quickflow.git
cd quickflow
./Scripts/fetch-model.sh # downloads small.en into models/
./build.sh              # this Mac's architecture
./build.sh --universal  # Apple Silicon + Intel
./package.sh            # dist/QuickFlow-3.0.dmg + SHA256SUMS
```

`build.sh` compiles whisper.cpp statically with Metal and Accelerate (first run only, a couple of minutes per architecture), compiles the Swift sources, assembles `QuickFlow.app`, bundles the best available model, and signs it. Full details, including how to sign with a Developer ID, are in [docs/BUILDING.md](docs/BUILDING.md).

## Documentation

| Document | Contents |
| --- | --- |
| [docs/INSTALL.md](docs/INSTALL.md) | Download, first launch, permissions, updating, uninstalling |
| [docs/USAGE.md](docs/USAGE.md) | Every feature, setting, and shortcut in detail |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How audio, decoding, and live subtitles actually work |
| [docs/BUILDING.md](docs/BUILDING.md) | Building, packaging, signing, releasing |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Permissions, hotkeys, silence, Gatekeeper |
| [docs/RELEASING.md](docs/RELEASING.md) | Cutting a release and publishing it |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Build, style, and review expectations |
| [SECURITY.md](SECURITY.md) | Data handling, network surface, reporting |
| [ROADMAP.md](ROADMAP.md) | What shipped and what is deliberately not done yet |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |

## Privacy

- No network calls. The app links no networking framework and has no analytics.
- Audio exists in RAM for the duration of a take and is discarded after transcription.
- The model file lives inside the app; nothing is downloaded at runtime.
- The last ten transcripts are kept locally in `UserDefaults` so you can recover an accidental paste. Clear them from the menu or with `defaults delete com.quickflow.app recentTranscripts`.
- Clipboard contents are snapshotted and restored around the paste, and never stored.

## Status

Version 3.0. Universal binary, macOS 13+. Ad-hoc signed: there is no Apple Developer ID behind this build, so Gatekeeper requires the one-time right-click or `xattr` step described above. The app has no auto-updater; check Releases for new versions.

## License

MIT. See [LICENSE](LICENSE).
