# Installing QuickFlow

One file, one drag, two switches. There is no installer package, no account, and nothing else to download — the speech model ships inside the app.

## Requirements

| | |
| --- | --- |
| macOS | 13 Ventura or later |
| Chip | Apple Silicon or Intel — the download is a universal binary |
| Disk | about 1 GB free (the 465 MB model is inside the app) |
| Network | only to download the DMG; the app itself never makes a network call |

## 1. Download the DMG

Open [Releases](https://github.com/morpheus762228/quickflow/releases) and download **`QuickFlow-3.0.dmg`** (about 450 MB), along with `SHA256SUMS`.

> **The repository is private for now.** A browser download therefore needs you signed in to GitHub on that machine. If you would rather not, use the command line below with `gh` already authenticated.

```bash
gh release download v3.0.0 --repo morpheus762228/quickflow \
  --pattern 'QuickFlow-3.0.dmg' --pattern 'SHA256SUMS'
```

Check the download before opening it:

```bash
shasum -a 256 QuickFlow-3.0.dmg
cat SHA256SUMS          # the two lines must be identical
```

## 2. Drag it into Applications

Double-click the DMG. Finder opens a window with **QuickFlow** on the left, an arrow, and the **Applications** folder on the right. Drag the app across the arrow, then eject the disk.

Terminal equivalent:

```bash
hdiutil attach QuickFlow-3.0.dmg -nobrowse
cp -R /Volumes/QuickFlow/QuickFlow.app /Applications/
hdiutil detach /Volumes/QuickFlow
xattr -dr com.apple.quarantine /Applications/QuickFlow.app
```

The `xattr` line is the same quarantine override described in step 3 — it saves you the right-click dance.

## 3. First launch

QuickFlow is signed ad-hoc, not notarized by Apple, so Gatekeeper stops the first double-click. That is expected, and it is a one-time step — the app is not damaged and nothing was mis-downloaded.

**Right-click (or Control-click) QuickFlow in Applications → Open → Open.**

If the only button offered is *Move to Bin*, close the dialog and use one of these instead:

- **System Settings → Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to the message about QuickFlow, or
- run once in Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/QuickFlow.app
  ```

Once it launches, the menu bar shows the QuickFlow waveform icon. There is no Dock icon and no main window.

## 4. Two permission switches

| Permission | Needed for | Without it |
| --- | --- | --- |
| **Microphone** | Recording your voice | Nothing can be transcribed |
| **Accessibility** | Pasting the transcript into the frontmost app | The text is still produced and copied to the clipboard, and you paste it yourself |

The welcome window asks for both with a button each; the same two rows live in the menu bar dropdown with live status, and clicking a red one opens the right pane in System Settings.

Grant **Microphone** in the dialog. For **Accessibility**, macOS opens **System Settings → Privacy & Security → Accessibility**: switch QuickFlow on, adding it with **+** or by dragging `/Applications/QuickFlow.app` in if the list is empty.

If the switch already looks on but QuickFlow still reports it as missing, the grant belongs to a previous build. The fix takes ten seconds:

```bash
tccutil reset Accessibility com.quickflow.app
```

then launch QuickFlow once and switch it on again. Details in [TROUBLESHOOTING.md](TROUBLESHOOTING.md#accessibility-says-off-but-system-settings-shows-it-on).

## 5. First dictation

1. Click into TextEdit (or Mail, Slack, your editor) and put the cursor where the text should go.
2. Press **⌥⌘R**.
3. Say a sentence.
4. Press **⌥⌘T**.

The text is pasted where the cursor was, usually within a second or so of stopping. If nothing happens, run the built-in diagnostic:

```bash
/Applications/QuickFlow.app/Contents/MacOS/QuickFlow --check
```

It prints permission status, installed models, and available input devices.

## Updating

Download the new DMG and drag the new app over the old one. macOS keeps your settings. A re-signed build has a different code identity, so the Microphone and Accessibility switches may need to be granted again — the `tccutil reset` above is the clean way to do that.

## Uninstalling

Quit QuickFlow from the menu bar, then drag `/Applications/QuickFlow.app` to the Bin. To remove the rest:

```bash
defaults delete com.quickflow.app
rm -rf ~/Library/Application\ Support/QuickFlow
tccutil reset Microphone com.quickflow.app
tccutil reset Accessibility com.quickflow.app
```

The last two lines matter for a clean reinstall: they drop the permission records that would otherwise point at a bundle that no longer exists.

## If something is wrong

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| "QuickFlow is damaged" | Quarantine flag, not damage | Right-click → Open, or `xattr -dr com.apple.quarantine` |
| App opens, no menu bar icon | Launch was blocked silently | Reopen from Applications, check Privacy & Security |
| Shortcuts do nothing | Accessibility not granted | Grant it, or use the menu bar Start/Finish |
| Transcript pasted nowhere | Accessibility missing | It was copied to the clipboard — paste it yourself |
| Empty takes | No input device, or a virtual one selected | Settings → Input, pick the built-in microphone |

The full list is in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
