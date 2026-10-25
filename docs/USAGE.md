# Using QuickFlow

QuickFlow lives in the menu bar. There is no main window and no Dock icon: you press a shortcut, talk, press another shortcut, and the text appears where your cursor is.

Installing, Gatekeeper, and the two permission switches are covered in [INSTALL.md](INSTALL.md); this guide assumes QuickFlow is installed and running.

## First run

On first launch QuickFlow shows a short welcome window with two permission rows:

| Permission | Why it is needed | What happens without it |
| --- | --- | --- |
| **Microphone** | Records your voice. | Nothing can be transcribed. |
| **Accessibility** | Sends ⌘V to the frontmost app so the transcript is pasted. | The transcript is still produced and copied to the clipboard; you paste it yourself. |

Grant Microphone with the button in the window. For Accessibility, macOS opens **System Settings → Privacy & Security → Accessibility**; add QuickFlow with the **+** button or by dragging `/Applications/QuickFlow.app` into the list, and make sure its switch is on.

Both rows also appear in the menu bar dropdown with live status, so you never have to guess which permission is missing. Clicking a red row opens the right pane in System Settings.

The welcome window can be reopened any time from the menu: **Quick Start…**.

## The daily loop

1. Put the cursor where the text should go — a Mail draft, a Slack message, an editor, a terminal.
2. Press **⌥⌘R**. The floating panel appears at the bottom of the screen with a red dot, a level meter, and a timer.
3. Talk normally.
4. Press **⌥⌘T**. The panel shows a spinner while the final decode runs, then the text is pasted.

While QuickFlow is recording, **Esc** cancels the take: audio is discarded, no transcript is produced, and nothing is pasted.

Defaults worth knowing:

- **Maximum take length is five minutes.** The timer keeps counting; anything beyond the cap is not recorded, so dictate long documents in sections.
- **A take with no speech is discarded** rather than pasted as an empty string or a hallucinated sentence.
- **The panel never steals focus**, so the app you were typing in stays frontmost and receives the paste.

## The floating panel

The panel has four states:

| State | What it looks like |
| --- | --- |
| Listening | Red dot, animated level bars (five bars that follow your voice), elapsed timer |
| Transcribing | Spinner and "Transcribing…" |
| Result | A short confirmation, or an error such as "No speech detected" |
| Live subtitles | The same listening header, with the transcript growing underneath in up to four lines |

The panel is click-through: it does not take clicks away from your work, and it hides itself a moment after the result is shown.

## Live subtitles

Live subtitles are **on by default**. Toggle them from the menu bar with **Live Subtitles**; the setting is remembered between launches and you can flip it mid-take.

How it behaves:

- Text appears in chunks roughly every 0.7 seconds, built from a rolling re-decode of the last ~12 seconds of audio.
- The panel grows from one to four lines, then keeps the newest text visible and lets older lines scroll off.
- Already-printed words are not printed again. If whisper re-times a sentence as the window slides, QuickFlow trims the overlapping words instead of duplicating them.
- The last half-second of audio is never promoted to "final" text, so a half-spoken word cannot get stuck on screen as if it were committed.
- On stop, the preview is discarded and one full decode of the entire take produces the text that is pasted.

The preview is a reading aid, not the deliverable. It can be a word or two behind, and it can revise itself; the pasted text is always the clean, whole-take result.

## Recent transcripts

The menu keeps the last **ten** transcripts under **Recent Transcripts**, each labelled with its first 48 characters. Clicking one copies it to the clipboard without pasting — useful when you dictated into the wrong window.

- **Copy Last Transcript** re-copies the most recent result.
- **Clear Recent Transcripts** empties the list.

Recent transcripts are stored locally in `UserDefaults` (`com.quickflow.app`). They never leave the machine.

## Settings

Open with **⌘,** or **Settings…** in the menu.

### Input

Choose the microphone. QuickFlow lists physical inputs and skips virtual devices such as BlackHole or Loopback when a real microphone is present, because a virtual device records silence unless something is routing audio into it. If you deliberately dictate from a virtual device, pick it explicitly.

### Model

Lists every `ggml-*.bin` found in the app bundle and in `~/Library/Application Support/QuickFlow/models`. Models are shown with their size. **Reveal Models Folder** opens that directory in Finder.

See [Models](#models) below for which one to pick.

### Language

`en` by default. Set `auto` for language detection, or a code such as `es`, `fr`, `de`, `ja`. Multilingual models (`large-v3-turbo`, `large-v3`) handle non-English best; the bundled `small.en` is English-only by design and is both faster and more accurate for English.

### Custom vocabulary

A free-text field for names, products, acronyms, and jargon: `QuickFlow, whisper.cpp, Nous Research, Kubernetes, JWT, gRPC`. It is passed to the model as an initial prompt, which biases decoding toward those spellings. Keep it to a line or two of the words that actually get mangled — a long prompt dilutes the effect.

This is the highest-leverage accuracy setting. If a colleague's name or your project's name comes out wrong every time, put it here.

### Paste automatically

On: the transcript is pasted into the frontmost app. Off: it is only placed on the clipboard, and the panel tells you so. Turn it off if you dictate into a remote session, a VM, or an app that mishandles synthetic ⌘V.

### Keep my clipboard

On: whatever you had copied before dictating is restored afterwards, so dictation does not destroy your clipboard. Off: the transcript stays on the clipboard after pasting. Turn it off if you want to paste the same text somewhere else immediately.

### Smart formatting

On by default. Applies, in order:

- removes `um`, `uh`, `uhm`, `erm`, `hmm` and their trailing punctuation;
- collapses stutters (`the the the` → `the`);
- fixes lowercase `i` and `i'm` / `i'll` / `i've` / `i'd`;
- removes doubled spaces and spaces before punctuation, collapses `!!` and `...` repetition;
- capitalises sentences (except in code);
- ends prose and email with a full stop if the model left it off.

Spoken punctuation — "period", "comma", "question mark", "new paragraph" — is handled by whisper itself, so it works with formatting off.

### Sound cues

A short tone when recording starts and stops. Useful when the panel is on another display or behind a window.

### Launch at login

Registers the app with `SMAppService`. QuickFlow then starts with your Mac and stays in the menu bar, so the first dictation after a reboot does not wait for a launch.

## Formatting styles

QuickFlow picks a style from the app that was frontmost when you started dictating:

| Style | Apps | Effect |
| --- | --- | --- |
| **email** | Mail, Outlook, Spark | Greeting and sign-off get paragraph breaks; sentence casing; trailing full stop |
| **chat** | Slack, Messages, Discord, Signal, WhatsApp, Teams, Messenger | No trailing full stop, no paragraph reflow |
| **code** | Xcode, VS Code, Cursor, Zed, Sublime, JetBrains IDEs, Terminal, iTerm | Preserves casing, no sentence capitalisation, no added punctuation |
| **prose** | Everything else | Sentence casing and a terminating full stop |

Override the automatic choice from the CLI with `--style prose|email|chat|code`.

## Keyboard shortcuts

| Shortcut | Scope | Action |
| --- | --- | --- |
| ⌥⌘R | Global | Start dictating |
| ⌥⌘T | Global | Stop and transcribe |
| Esc | Only while recording | Cancel the take |
| ⌘, | App menu | Open Settings |

Shortcuts are registered with Carbon `RegisterEventHotKey`, so they work regardless of which app has focus. If ⌥⌘R does nothing, another app already owns that combination — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-shortcut-does-nothing).

## Command line

The app binary is also the CLI. It is handy for batch work, benchmarking, and checking a microphone without opening the UI.

```bash
QF=/Applications/QuickFlow.app/Contents/MacOS/QuickFlow

$QF --help                                  # usage
$QF --check                                 # permissions, models, devices
$QF --devices                               # input devices with UIDs
$QF --transcribe interview.wav              # plain transcript
$QF --transcribe interview.wav --clean      # with formatting (prose)
$QF --transcribe notes.m4a --clean --style chat
$QF --dictate                               # record, stop on Return, print
```

`--transcribe` accepts any audio format AVFoundation can decode (wav, m4a, mp3, caf, aiff, mp4) and resamples to 16 kHz mono internally. Up to 30 minutes per file.

Output: the transcript goes to **stdout**, timings and model loading information go to **stderr**, so `> out.txt` is safe.

`--dictate` is the fastest way to test a microphone and a model without involving Accessibility or the clipboard.

### Developer switches

These exist for verification without screen capture and are documented here so they are not mistaken for user features:

```bash
$QF --live-preview file.wav       # run the live-subtitle pipeline over a file, printing each frame
$QF --render-welcome out.png      # render the welcome window offscreen
$QF --render-live out.png         # render the panel with subtitles offscreen
```

## Models

| File | Size | Notes |
| --- | --- | --- |
| `ggml-tiny.en.bin` | 75 MB | Fastest and smallest. Noticeably worse on names and punctuation. Emergency use. |
| `ggml-base.en.bin` | 141 MB | Good for short commands, weaker on long sentences. |
| `ggml-small.en.bin` | 465 MB | **Bundled default.** The accuracy/speed sweet spot at ~29× realtime. |
| `ggml-medium.en.bin` | 1.5 GB | Better on accented speech and noisy rooms, several times slower. |
| `ggml-large-v3-turbo.bin` | 1.5 GB | Best accuracy, multilingual; wants RAM and a recent Mac. |

Install a model by dropping the file into:

```
~/Library/Application Support/QuickFlow/models/
```

then pick it in **Settings → Model**. No restart needed. Download links are on the [whisper.cpp model page](https://huggingface.co/ggerganov/whisper.cpp/tree/main).

When several models are present, the automatic choice is `large-v3-turbo`, then `small.en`, then `base.en`, then `medium.en`, then `tiny.en`.

## Data and files

| What | Where |
| --- | --- |
| Preferences, recents, onboarding flag | `~/Library/Preferences/com.quickflow.app.plist` |
| Extra models | `~/Library/Application Support/QuickFlow/models/` |
| Bundled model | `QuickFlow.app/Contents/Resources/models/` |
| Logs | `log show --predicate 'process == "QuickFlow"' --last 5m` |

QuickFlow keeps **no audio files**. If dictation goes wrong and you want a clean slate:

```bash
defaults delete com.quickflow.app            # all preferences and recents
tccutil reset Microphone com.quickflow.app
tccutil reset Accessibility com.quickflow.app
```

Then relaunch and grant permissions again.

## Uninstall

1. Quit QuickFlow from the menu.
2. Drag `/Applications/QuickFlow.app` to the Trash.
3. Remove leftovers:

```bash
defaults delete com.quickflow.app
rm -r ~/Library/Application\ Support/QuickFlow
tccutil reset Microphone com.quickflow.app
tccutil reset Accessibility com.quickflow.app
```

## Limits

- One take is capped at five minutes; long-form dictation is meant to be done in sections.
- Live subtitles lag speech by roughly a second and may revise the last few words.
- The bundled model is English-only. Multilingual work needs a multilingual model.
- Intel Macs run the same code path but without unified memory or the same GPU throughput.
- No auto-update, no iCloud sync, no per-app shortcut remapping yet. See [ROADMAP.md](../ROADMAP.md).
