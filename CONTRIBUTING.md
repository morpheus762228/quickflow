# Contributing

QuickFlow is a small, single-purpose app: press two shortcuts, get clean text, nothing leaves the Mac. Contributions are welcome when they respect that shape.

## Ground rules

1. **Privacy is a hard constraint.** No networking frameworks, no telemetry, no crash reporting SDKs, no "check for updates" pings. A PR that adds an HTTP client will be declined regardless of how useful the feature is.
2. **No new runtime dependencies.** The app ships as one binary with whisper.cpp statically linked. Swift Package Manager dependencies, Homebrew libraries, and Python helpers are all out of scope.
3. **Native UI only.** AppKit/SwiftUI. No Electron, no web views for app chrome.
4. **Keep it local.** Models are files on disk, not downloads at runtime.

## Before you start

- For anything larger than a bug fix, open an issue first. The interesting design decisions here are about latency and text quality, and it is worth agreeing on the approach before you spend an evening on it.
- Check [ROADMAP.md](../ROADMAP.md) for what is deliberately not built yet.

## Build and run

```bash
./Scripts/fetch-model.sh     # once
./build.sh                   # this architecture
open QuickFlow.app
```

Full detail, including universal builds and signing, is in [docs/BUILDING.md](BUILDING.md).

Note that every rebuild changes the code signature and therefore invalidates Microphone and Accessibility for the new binary. During UI work that does not matter; for end-to-end testing, expect one re-approval per cycle:

```bash
tccutil reset Microphone com.quickflow.app
tccutil reset Accessibility com.quickflow.app
```

## Code style

- Swift 5 language mode, no external formatter enforced. Match the file you are editing: four-space indent, `// MARK:` sections, early returns, no force unwraps outside of main-thread UI code that cannot fail.
- Prefer small, pure functions for text work. `TextCleaner` and `SmartFormatter` are deliberately free of AppKit and `UserDefaults` so they can be reasoned about and exercised from the CLI.
- Anything that touches a whisper context must hold `WhisperEngine.decodeLock`. The context is not thread-safe; live preview and final decode both use it.
- Never do work on the audio render thread. Copy the buffer out, then hand off.
- No new `print` in the GUI path — use `NSLog`, which shows up in `log show` with the process name.

## Testing

There is no automated test suite yet. A change is expected to be verified with real execution:

```bash
Q=QuickFlow.app/Contents/MacOS/QuickFlow
$Q --check
$Q --transcribe vendor/whisper.cpp/samples/jfk.wav
$Q --transcribe vendor/whisper.cpp/samples/jfk.wav --clean --style email
$Q --live-preview vendor/whisper.cpp/samples/jfk.wav
$Q --render-live /tmp/panel.png
```

Plus a manual pass for anything touching the hot path:

- [ ] ⌥⌘R starts, ⌥⌘T stops and pastes into a non-QuickFlow app
- [ ] Esc cancels without pasting
- [ ] A silent take is discarded, not pasted
- [ ] With live subtitles on, a 30-second take shows text without duplicated words
- [ ] With Accessibility revoked, the transcript still lands on the clipboard

Paste the command output or a screenshot in the PR description. "Works on my machine" without evidence is not reviewable.

## Commit and PR

- One logical change per PR. Formatting-only churn mixed with behaviour changes is hard to review and will be sent back.
- Commit messages: imperative subject under ~70 characters, then a short body explaining the *why* when it is not obvious.
- Update `CHANGELOG.md` for user-visible changes and the relevant doc in `docs/` when behaviour or settings change.
- If you change `Info.plist`'s version, say so in the PR — packaging and the DMG name derive from it.

## Reporting bugs

Include macOS version, Mac model, selected model, the output of `--check`, and the relevant lines from:

```bash
log show --predicate 'process == "QuickFlow"' --last 10m --style compact
```

Do not attach audio you would not share publicly. A description of what you said and what came out is usually enough. Security issues: see [SECURITY.md](../SECURITY.md), not a public issue.

## License

By contributing you agree your work is licensed under the MIT license in [LICENSE](../LICENSE).
