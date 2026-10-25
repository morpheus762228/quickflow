# QuickFlow roadmap

What is shipped, what is still open, and why. Effort is rough calendar/engineering cost for one focused person; impact is 1–5 across performance, experience, and real work.

## Shipped in 3.0

| Thing | Why it mattered |
| --- | --- |
| Native Swift + whisper.cpp, no Python | Removed a subprocess and a runtime from the hot path |
| Metal + Accelerate, static build | 29× realtime on `small.en`; no Homebrew dependency |
| Warm-up at launch | First dictation is as fast as the tenth |
| Menu bar panel with level meter and timer | Confidence it is listening, without a window |
| Global hotkeys + Esc cancel | One-handed start/stop, no ruined takes |
| Live subtitles in the panel | Long takes are readable while you speak, not a black box |
| Smart formatting, spoken punctuation, per-app style | Output you can send without editing |
| Custom vocabulary as whisper prompt | The single biggest accuracy win for real work |
| Input picker that skips virtual mics | Fixes the "recorded silence" failure mode |
| Clipboard snapshot/restore, recents menu | Pasting does not destroy what you copied; mistakes are recoverable |
| First-run window with in-app permission prompts | Removes most "nothing happened" support pain |
| Launch at login (`SMAppService`) | A dictation app you do not have to remember to start |
| Universal binary, DMG with Read Me, SHA256SUMS | "Download it from GitHub and use it" actually works |
| Tagged release with the DMG attached | The promise, delivered |
| CLI: `--dictate`, `--transcribe`, `--check`, `--devices` | Scriptable, and the way builds get verified without a mic |

## Open — worth doing next

| Item | Impact | Effort | Notes |
| --- | --- | --- | --- |
| Automated tests + CI for formatter, cleaner, WAV, audio decode | 4 | 3 | Pure functions; regressions there are silent and embarrassing |
| Notarization with a Developer ID | 5 | 2 | $99/yr removes every Gatekeeper warning and is the single biggest install obstacle left |
| In-app model manager (download, delete, progress) | 4 | 3 | Replaces the Finder-and-Hugging-Face ritual |
| Custom hotkey recorder | 4 | 2 | ⌥⌘R collides with some editors and window managers |
| Visible, editable per-app formatting rules | 3 | 2 | Detection exists; it is not user-visible |

## Open — real but not load-bearing

| Item | Impact | Effort | Notes |
| --- | --- | --- | --- |
| History window with search and retention | 3 | 3 | The recents menu covers the common case |
| Editing voice commands ("scratch that", "make that a heading") | 3 | 2 | Punctuation is handled; selection and correction are the next layer |
| Quantized bundled model (q5_0) | 3 | 2 | ~180 MB instead of 465 MB for a small WER cost |
| Auto-update | 3 | 3 | Only worth it once releases are frequent; adds networking code, which is currently the point of not having any |
| Translation mode | 2 | 2 | Whisper supports it; niche for dictation |
| iOS companion | 2 | 5 | A different product |

## Deliberately not doing

- **Telemetry.** Not even opt-in aggregate. The app has no networking code and that is a feature people can verify with `otool`.
- **Cloud models.** "Fully local" is the product. An opt-in cloud mode would change what the privacy claims mean.
- **Audio retention for debugging.** Opt-in or not, writing takes to disk contradicts the pitch. Reproduce with `--transcribe` on a file the reporter chooses to share.

## What "done" means

Not "it builds." Done means a stranger downloads the DMG from Releases, drags it to Applications, gets through Gatekeeper and two permission prompts without reading a wiki, dictates a sentence into Mail, and the sentence is correct — on an M1 MacBook Air and on an Intel Mac mini.

That is true as of 3.0 except for the Gatekeeper prompt, which stays until the app is notarized.
