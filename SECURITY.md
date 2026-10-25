# Security and privacy

QuickFlow is a dictation tool for people who do not want their voice on someone else's server. The security properties below are the product, not a checkbox.

## What the app does with your data

| Data | Handling |
| --- | --- |
| Microphone audio | Held in RAM for the duration of a take, transcribed locally, then discarded. Never written to disk by the app. |
| Transcripts | Placed on the clipboard, pasted into the frontmost app, and kept in a local list of the last 10 for recovery. |
| Preferences | `~/Library/Preferences/com.quickflow.app.plist`. |
| Models | Local files, bundled or in `~/Library/Application Support/QuickFlow/models/`. |
| Clipboard | Snapshotted before pasting and restored afterwards. Not logged, not stored. |

## Network

The app links no networking framework. Verify on a built binary:

```bash
otool -L QuickFlow.app/Contents/MacOS/QuickFlow | grep -iE 'cfnetwork|network|curl|socket'
# no output
```

There is no update check, no analytics, no crash reporter, no license call, and no remote model fetch. whisper.cpp runs in-process; the model file is read from disk. The only network activity in the project is `build.sh` cloning whisper.cpp and `Scripts/fetch-model.sh` downloading a model — both are developer actions, not app behaviour.

## Permissions

- **Microphone** — required; without it there is no audio.
- **Accessibility** — required only for pasting keystrokes. Without it the transcript still lands on the clipboard.
- **Nothing else.** No screen recording, no full disk access, no input monitoring beyond the Carbon hot key, no automation entitlements.

Entitlements are in [QuickFlow.entitlements](../QuickFlow.entitlements): a single `com.apple.security.device.audio-input`. App sandbox is off (it needs Accessibility and global hot keys, which are incompatible with the sandbox) and the hardened runtime is enabled at signing time (`flags=adhoc,runtime`).

## Trust boundary

QuickFlow trusts the model file it loads and the whisper.cpp code compiled into it. It does not trust the network, because it does not use it. If you install a model downloaded from an untrusted source, you are trusting that file's contents with your audio — the same as any local model. The bundled `small.en` comes from the official `ggerganov/whisper.cpp` Hugging Face repository.

## Code signing

Release builds are **ad-hoc signed**, not notarized by Apple. Consequences:

- Gatekeeper requires a one-time right-click → Open, or `xattr -dr com.apple.quarantine`.
- macOS ties permission grants to the binary's `cdhash`; rebuilding invalidates them.
- There is no Apple-verified publisher identity behind the download. If that matters for your threat model, build from source with `QF_SIGN_IDENTITY` set to your own Developer ID, or verify the release DMG against `SHA256SUMS`.

Verify a download:

```bash
shasum -a 256 QuickFlow-3.0.dmg
codesign -dv --verbose=4 /Applications/QuickFlow.app
```

## Known limitations

- The last 10 transcripts are stored in plain `UserDefaults`, unencrypted. They are readable by anything running as your user. Clear them from the menu when they are no longer useful.
- Clipboard contents briefly include the transcript. Other clipboard managers may capture it; that is outside QuickFlow's control.
- Live subtitles decode a rolling window of the take in memory; that buffer exists until the take ends.
- Audio is captured with the normal microphone permission, so any other app with microphone access can capture concurrently. QuickFlow does not detect or prevent that.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository (**Security → Report a vulnerability**). Please do not open a public issue for anything that could expose audio, transcripts, or clipboard contents.

Include the version (`QuickFlow --check` prints it), macOS version, and a description of the issue. A proof of concept helps but is not required. Expect an acknowledgement within a week; this is a single-maintainer project, not a company with an on-call rotation.

## Supported versions

Only the latest release receives security fixes. There are no maintained older branches.
