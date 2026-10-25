# QuickFlow roadmap — weighted, not wishful

Weights answer one question: **does this make dictation faster, nicer to use, or actually usable for real work?** Effort is rough calendar/engineering cost for one focused person.

- **Impact** 1–5 across performance, experience, and workload (5 = changes whether you reach for the app)
- **Effort** 1–5 (1 = an afternoon, 5 = a week or more)
- **Score** = Impact ÷ Effort
- **Verdict**: **Must** (do before public), **Should** (next), **Could** (when it earns its keep), **Later**

## Shipped in 3.0

| Thing | Why it mattered |
| --- | --- |
| Native Swift + whisper.cpp (no Python) | Removed a subprocess and a runtime from the hot path |
| Metal + Accelerate, static build | 29× realtime on `small.en`; no Homebrew dependency |
| Warm-up at launch | First dictation is as fast as the tenth |
| Menu bar HUD with level meter | Confidence that it's listening, without a window |
| Global hotkeys + Esc cancel | One-handed start/stop, no ruined takes |
| Smart formatting + spoken punctuation | Output you can send without editing |
| Input device picker that skips virtual mics | Fixes the "recorded silence" failure mode |
| Clipboard snapshot/restore | Pasting doesn't destroy what you had copied |
| Recents menu | Recovery for the "I pasted over it" moment |
| Icon, `.app` bundle, CLI | Something you can double-click and also script |
| Live subtitles in the HUD | Long takes are readable while you speak, not a black box |

## Must — before calling it shippable

| # | Item | Impact | Effort | Score | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Install path: DMG, README, Gatekeeper instructions | 5 | 1 | **5.0** | A download nobody can open is a bug |
| 2 | Tagged GitHub release with the DMG attached | 5 | 1 | **5.0** | The actual "download off GitHub" promise |
| 3 | Universal binary (Intel + Apple Silicon) | 4 | 3 | 1.3 | "Any Mac" includes Intel; small.en on Intel is ~1–2× realtime |
| 4 | Automated tests + CI for formatter, cleaner, WAV, audio decode | 4 | 3 | 1.3 | These are pure functions; regressions here are silent and embarrassing |
| 5 | First-run onboarding: permissions, hotkey demo, model status | 4 | 2 | 2.0 | Most support pain for a menu bar app is "nothing happened" |

## Should — the experience gap over built-in dictation

| # | Item | Impact | Effort | Score | Notes |
| --- | --- | --- | --- | --- | --- |
| 6 | In-app model manager (download/delete, progress) | 4 | 3 | 1.3 | Removes the Finder-and-Hugging-Face ritual |
| 7 | Custom hotkey recorder | 4 | 2 | 2.0 | ⌥⌘R collides with some editors |
| 8 | Vocabulary UI with initial prompt | 4 | 2 | 2.0 | Names and jargon are where Whisper loses trust |
| 9 | Streaming partial text in the HUD | 5 | 5 | 1.0 | **Shipped in 3.0** as rolling-window subtitles |
| 10 | Notarization with a Developer ID | 5 | 2 | 2.5 | Costs $99/yr; removes every Gatekeeper warning |
| 11 | Launch at login on by default after onboarding | 3 | 1 | 3.0 | A dictation app you have to remember to start is not a dictation app |
| 12 | Per-app formatting rules (Mail vs. Xcode vs. Slack) | 3 | 2 | 1.5 | Style detection exists; make it visible and editable |

## Could — real but not load-bearing

| # | Item | Impact | Effort | Score | Notes |
| --- | --- | --- | --- | --- | --- |
| 13 | History window with search and retention policy | 3 | 3 | 1.0 | Recents menu covers the common case |
| 14 | Voice commands ("new paragraph", "scratch that") | 3 | 2 | 1.5 | Punctuation already handled; editing commands are next |
| 15 | Quantized bundled model (q5_0) | 3 | 2 | 1.5 | ~180 MB instead of 465 MB, small WER cost |
| 16 | Sparkle auto-updates | 3 | 3 | 1.0 | Only worth it once releases are frequent |
| 17 | Translation mode | 2 | 2 | 1.0 | Whisper supports it; niche for dictation |
| 18 | iOS companion | 2 | 5 | 0.4 | Different product |

## Later

- **The side feature** — deliberately deferred until the core app is distribution-ready.
- Audio retention for debugging (opt-in, auto-deleted).
- Telemetry — only ever opt-in, aggregate, and never transcript content.

## What "done" means

Not "it builds." Done means: a stranger downloads a DMG from the Releases page, drags it to Applications, gets through Gatekeeper and two permission prompts without reading a wiki, dictates a sentence into Mail, and the sentence is correct — on an M1 MacBook Air and on an Intel Mac mini.
