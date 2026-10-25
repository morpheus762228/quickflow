# Troubleshooting

Start with the built-in check — it reports permissions, models, and input devices in one screen:

```bash
/Applications/QuickFlow.app/Contents/MacOS/QuickFlow --check
```

Then open the menu bar dropdown. Every failure the app knows about is surfaced there rather than swallowed: microphone status, accessibility status, missing model, hotkey conflict.

One caveat on `--check`: run from a terminal it inherits the terminal's TCC identity, so it can print `Microphone: not requested` even when the app itself is fine. Trust the values when it still reports the app's model and input device, and trust the menu bar for permission state.

## The app will not open

**"QuickFlow is damaged and should be moved to the Trash"** or **"Apple cannot check it for malicious software"**.

This is Gatekeeper reacting to an unsigned-for-distribution app, not a corrupt download. Either right-click the app → **Open** → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/QuickFlow.app
open /Applications/QuickFlow.app
```

On macOS 15, after a blocked launch, also check **System Settings → Privacy & Security** and click **Open Anyway**.

Verify the download first if you like:

```bash
shasum -a 256 ~/Downloads/QuickFlow-3.0.dmg
cat SHA256SUMS   # from the release
```

## The shortcut does nothing

1. Is QuickFlow running? Look for the waveform in the menu bar. If it is not there, `open /Applications/QuickFlow.app`.
2. Is another app using ⌥⌘R? Raycast, Alfred workflows, window managers, and some IDEs claim similar combinations. Quit the suspect and try again; Carbon does not report cross-process conflicts, so the app cannot detect this for you.
3. Check the log:

   ```bash
   log show --predicate 'process == "QuickFlow"' --last 5m --style compact | grep -i hotkey
   ```

   A healthy launch prints `RegisterEventHotKey … mods=2304 … OK` twice.
4. Is an *older* copy running? Version 1.0 used the same shortcut, so a leftover process answers first:

   ```bash
   pgrep -fl QuickFlow
   pkill -x QuickFlow
   open /Applications/QuickFlow.app
   ```

## The panel appears, but nothing is transcribed

**Microphone permission.** The menu shows **Microphone: Off** in red if it is missing. Click it, enable QuickFlow in System Settings, then relaunch the app.

**Wrong input device.** If the system default input is a virtual device (BlackHole, Loopback, an aggregate), it records silence. QuickFlow prefers a physical microphone automatically, but an explicit wrong choice in **Settings → Input** overrides that. Run `--devices` and pick the built-in mic.

**The take was silent.** A take whose RMS stays below `0.0016` is discarded on purpose, because whisper invents sentences when fed silence. Speak, then check the meter moves.

**Input level is very low.** Check the mic in **System Settings → Sound → Input**; a level near zero produces nothing usable regardless of the app.

## Accessibility says off, but System Settings shows it on

The classic ad-hoc signing symptom. macOS stores the grant against the code requirement of the binary that was approved; rebuilding changes the `cdhash`, so the old grant no longer matches and the toggle you see belongs to a stale entry. The switch reads on, the app still gets denied — because they are two different records.

```bash
pkill -x QuickFlow
tccutil reset Accessibility com.quickflow.app     # reports one line per stale entry removed
open /Applications/QuickFlow.app
```

Approve QuickFlow once the fresh prompt appears. If `tccutil` reported more than one entry, that was the whole problem: every rebuild left another ghost grant behind, and System Settings was showing you one of them rather than the binary in `/Applications`.

Verify the grant actually landed instead of trusting the switch — quit and relaunch QuickFlow (relaunching does not change the signature), then read TCC's own decision:

```bash
pid=$(pgrep -x QuickFlow)
log show --last 1m --predicate 'process == "tccd"' --style compact | grep "msgID=${pid}\." | grep AUTHREQ_RESULT
```

`authValue=2` means allowed; `authValue=1` means the request was denied and the toggle you see is the stale one. If System Settings lists duplicate QuickFlow rows, remove them with **−** and re-add `/Applications/QuickFlow.app` with **+**.

The cause is also visible in the log as `Failed to match existing code requirement … cdhash`. The durable fix is to stop shipping an ad-hoc signature — sign with a Developer ID certificate, or at minimum a self-signed one, so the code requirement identifies the signer rather than each build's cdhash.

## It pastes into the wrong place

QuickFlow pastes into whatever is frontmost at the moment it finishes. If you click another window while it is transcribing, that window gets the text.

- Wait for the "Pasted" confirmation before switching apps.
- Turn off **Paste automatically** to get clipboard-only behaviour, then paste deliberately.
- In remote desktop sessions, VMs, and some Electron apps, synthetic ⌘V is ignored. Clipboard-only mode is the workaround.

## Transcripts are wrong, repetitive, or hallucinated

| Symptom | Cause | Fix |
| --- | --- | --- |
| A sentence appears that nobody said | Silence or near-silence decoded anyway | Already guarded, but a very quiet mic can still trigger it; raise input gain |
| Names and jargon always wrong | Model has never seen them | Add them to **Custom vocabulary** |
| Words repeated at the start | Live preview overlap | Preview only; the pasted text comes from the full decode. If it persists in the pasted text, please report it with the audio |
| Punctuation missing | Spoken punctuation not used, or `chat` style | Say "period"; check the app was detected as prose/email, not chat |
| Everything lowercase | Detected as `code` style | That is intentional for editors and terminals; dictate elsewhere or use `--style prose` in the CLI |
| Accents or noisy rooms defeat it | `small.en` limits | Try `medium.en` or `large-v3-turbo` |

## It is slow

- **First take after launch** should be fast because of warm-up. If it is not, look for `warmUp` in the log; a missing model falls back to no warm-up.
- **Large model** — `medium.en` and `large-v3-turbo` are several times slower than `small.en`. Check **Settings → Model**.
- **Intel Mac** — no unified memory and weaker Metal; expect roughly real-time on `small.en`.
- **Live subtitles** decode in the background about twice a second. On an older machine, turning them off noticeably reduces sustained CPU.

## Model not found

```
~/Library/Application Support/QuickFlow/models/
```

is where extra models go. The bundled model lives at `QuickFlow.app/Contents/Resources/models/`. Confirm what the app sees:

```bash
/Applications/QuickFlow.app/Contents/MacOS/QuickFlow --check
```

If you moved the app out of `/Applications`, the bundled model is still inside it; if you deleted `Contents/Resources/models`, reinstall or drop a model into Application Support.

## "No speech detected" every time

In order:

1. `--devices` — is the default input the mic you think it is?
2. **System Settings → Sound → Input** — does the meter move when you talk?
3. `--dictate` — records and prints without Accessibility or clipboard involved. If this works, the problem is injection, not audio.
4. Reset permissions and relaunch (see above).

## Start over

```bash
pkill -x QuickFlow
defaults delete com.quickflow.app
rm -r ~/Library/Application\ Support/QuickFlow
tccutil reset Microphone com.quickflow.app
tccutil reset Accessibility com.quickflow.app
open /Applications/QuickFlow.app
```

This removes preferences, recents, extra models, and both permission grants. The bundled model is untouched.

## Collecting a useful report

```bash
log show --predicate 'process == "QuickFlow"' --last 10m --style compact > ~/Desktop/quickflow.log
/Applications/QuickFlow.app/Contents/MacOS/QuickFlow --check > ~/Desktop/quickflow-check.txt
```

Include macOS version, Mac model (`sysctl -n machdep.cpu.brand_string`), and which model is selected. Do not attach audio you would not share publicly; a description of the failure is usually enough. Crash reports live in `~/Library/Logs/DiagnosticReports/`.
