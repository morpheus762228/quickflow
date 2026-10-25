# Building QuickFlow

## Requirements

| Tool | Version | Notes |
| --- | --- | --- |
| macOS | 13.0+ | The deployment target is 13.0; building on a newer macOS is fine |
| Xcode Command Line Tools | any recent | `xcode-select --install`, provides `swiftc` and `codesign` |
| CMake | 3.20+ | `brew install cmake` |
| Git, curl | system | Used to fetch whisper.cpp and models |

No Xcode project, no CocoaPods, no SwiftPM manifest. The build is a shell script around `swiftc`.

## Quick start

```bash
git clone https://github.com/morpheus762228/quickflow.git
cd quickflow

./Scripts/fetch-model.sh          # ggml-small.en.bin (465 MB) into models/
./build.sh --universal            # first run also builds whisper.cpp (~2 min)
open QuickFlow.app
```

`models/` and `vendor/` are not in the repository — the model is too large for GitHub, and whisper.cpp is cloned at the pinned tag on first build.

## What `build.sh` does

1. **whisper.cpp.** If `vendor/whisper.cpp/build/src/libwhisper.a` is missing, clones `ggml-org/whisper.cpp` at **v1.7.6** and configures it with:

   ```
   -DCMAKE_BUILD_TYPE=Release
   -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
   -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF
   -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON
   -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF
   ```

   Static libraries plus an embedded Metal library mean the finished app is one self-contained binary: nothing to install, no dylib path to fix, no runtime download.

2. **Swift.** Compiles `Sources/*.swift` with `-parse-as-library -O -wmo`, the Objective-C bridge header, and whisper's include paths, linking the six static archives and AppKit, Carbon, AVFoundation, CoreAudio, UserNotifications, Metal, MetalKit, Accelerate.

3. **Bundle.** Assembles `QuickFlow.app` with `Info.plist`, the icon, the executable, and — if a model exists in `models/` — `Contents/Resources/models/`.

4. **Sign.** `codesign --force --options runtime --entitlements QuickFlow.entitlements --sign -`. Ad-hoc by default.

### Universal build

`./build.sh --universal` additionally configures a second whisper.cpp tree (`vendor/whisper.cpp/build-x86`) with `-DCMAKE_OSX_ARCHITECTURES=x86_64`, compiles Swift twice with explicit `-target` triples, and `lipo`s the two executables. `GGML_NATIVE=OFF` is required here: a native-optimised build bakes in AVX-512 flags that crash on older Intel Macs.

Verify:

```bash
lipo -info QuickFlow.app/Contents/MacOS/QuickFlow
# Architectures in the fat file ... are: x86_64 arm64
```

## Models

`build.sh` bundles the first of these it finds in `models/`: `ggml-small.en.bin`, `ggml-base.en.bin`, `ggml-large-v3-turbo.bin`. Override explicitly:

```bash
QF_MODEL=~/Downloads/ggml-medium.en.bin ./build.sh
```

If no model is bundled, the app still builds and runs but asks for a model on first launch — useful for a source checkout, not for a release.

`Scripts/fetch-model.sh` downloads from `huggingface.co/ggerganov/whisper.cpp` into `models/` with progress, a sanity size check, and the sha256 printed at the end. Set `QF_MODEL_DEST` to put it elsewhere.

## Signing

Ad-hoc (`-`) is the default and is enough to run locally. Two consequences:

- Gatekeeper blocks the first launch of a downloaded copy until the user right-click-opens it or clears the quarantine attribute.
- TCC grants are tied to the `cdhash`, which changes on every build. After replacing the app, reset and re-approve:

  ```bash
  tccutil reset Microphone com.quickflow.app
  tccutil reset Accessibility com.quickflow.app
  ```

With a Developer ID, sign properly instead:

```bash
QF_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh --universal
```

That adds `--timestamp` so the signature survives past the certificate's expiry. Notarize and staple before shipping:

```bash
ditto -c -k --keepParent QuickFlow.app QuickFlow.zip
xcrun notarytool submit QuickFlow.zip --keychain-profile quickflow --wait
xcrun stapler staple QuickFlow.app
spctl -a -vvv -t install QuickFlow.app   # should say "accepted, Notarized Developer ID"
```

Notarization needs a paid Apple Developer account; this repository ships ad-hoc builds because it does not have one.

## Packaging

```bash
./build.sh --universal
./package.sh
```

`package.sh` stages the app with an `/Applications` symlink, strips extended attributes (they inflate the image), and writes a compressed `dist/QuickFlow-3.0.dmg` plus `dist/SHA256SUMS`.

The Finder window people see when they open the DMG — brand background, app on the left, arrow, Applications on the right — comes from [`dmgbuild`](https://github.com/dmgbuild/dmgbuild), a packaging-time Python tool. `package.sh` uses it when the `dmgbuild` executable is on `PATH` and silently falls back to a plain `hdiutil` image without the window dressing when it is not, so builds never fail over it:

```bash
python3 -m venv .venv-dmg && . .venv-dmg/bin/activate
pip install dmgbuild
./package.sh
```

The window layout is defined in `Scripts/dmg_settings.py` (window rect, icon size, icon positions) and the artwork by `Scripts/make_dmg_background.swift`, which needs nothing beyond the Swift toolchain:

```bash
swift Scripts/make_dmg_background.swift assets/dmg-background.png 1
swift Scripts/make_dmg_background.swift assets/dmg-background@2x.png 2
```

The artwork is sized to the window's **content** area, not its frame: a 600×400 Finder window has a 28 pt title bar, so the image is 600×372 pt (600×372 px at 1×, 1200×744 px at 2×). `dmgbuild` spots the `@2x` sibling and packs both into one HiDPI TIFF, which is what makes the background sharp on Retina displays without scaling the 1× art up.

The three pieces must agree: the arrow drawn at `x: 300, y: 176` sits between the icon slots `(160, 176)` and `(440, 176)` in `dmg_settings.py`, and `ICON_ROW_Y` in the renderer is the same 176. Change one and re-render the other.

The DMG is about 450 MB because it contains the 465 MB `small.en` model compressed. Nothing else is padded in.

## Project layout

```
Sources/
  AppDelegate.swift      menu bar item, dictation flow, recents, menu state
  HUD.swift              floating panel, level meter, live subtitle block
  LiveTranscriber.swift  rolling-window preview decode
  WhisperEngine.swift    whisper.cpp wrapper, model loading, decode lock
  AudioRecorder.swift    AVAudioEngine tap → 16 kHz mono Int16
  AudioFile.swift        file decoding for --transcribe
  WAV.swift              WAV writer/reader helpers
  Devices.swift          CoreAudio input device enumeration
  TextCleaner.swift      filler/stutter/spacing rules, per-app style
  SmartFormatter.swift   email layout
  TextInjector.swift     pasteboard snapshot, ⌘V, restore
  HotKeyManager.swift    Carbon global hot keys
  Permissions.swift      microphone + accessibility checks and prompts
  Preferences.swift      UserDefaults keys and defaults
  SettingsWindow.swift   AppKit settings UI
  WelcomeWindow.swift    first-run window
  CLI.swift              argument parsing and the non-GUI modes
  ModelStore.swift       model discovery, app-support paths
  WhisperBridge.h        C bridge to whisper.h
Scripts/
  fetch-model.sh         model downloader
  make_icon.swift        regenerates the icon with AppKit, no dependencies
  make_dmg_background.swift  renders the DMG window artwork, also AppKit/SwiftUI only
  dmg_settings.py        dmgbuild layout: window rect, icon size and positions
assets/                  QuickFlow.icns, DMG background, PNG sources, older Pillow script
docs/                    user and developer documentation
legacy/                  1.0 Python implementation, archived, not built
vendor/                  whisper.cpp checkout (git-ignored)
models/                  ggml models (git-ignored)
```

To add a source file, drop it in `Sources/`; the `Sources/*.swift` glob picks it up. To bump the version, change `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` (both are used by `build.sh` and `package.sh`) and add a `CHANGELOG.md` entry.

## Verifying a build without a microphone

The binary carries three development switches specifically so a build can be checked in CI or over SSH:

```bash
Q=QuickFlow.app/Contents/MacOS/QuickFlow
$Q --check                                   # permissions, models, devices
$Q --transcribe vendor/whisper.cpp/samples/jfk.wav   # needs a model; decodes a fixture
$Q --live-preview vendor/whisper.cpp/samples/jfk.wav # prints each live-subtitle frame
$Q --render-live /tmp/panel.png              # renders the panel offscreen
$Q --render-welcome /tmp/welcome.png         # renders the welcome window offscreen
```

`--render-*` uses `cacheDisplay` into a bitmap and needs no screen-recording permission, which is why the screenshots in this repository are reproducible.

There is no automated test suite yet; these commands are the test plan. See [CONTRIBUTING.md](../CONTRIBUTING.md).

## Rebuilding during development

Rebuilding replaces `QuickFlow.app`, which changes the code signature, which invalidates Microphone and Accessibility for the new binary. For UI work this is invisible; for end-to-end testing, budget one `tccutil reset` + re-approval per cycle, or keep a stable signing identity.

The app is a single process with no hot reload. `pkill -x QuickFlow` before installing a new copy, or you will end up testing the old process — which has happened.
