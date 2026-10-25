# Releasing

The release artifact is a DMG with the app, an `/Applications` symlink, a plain-text Read Me, and a checksum published beside it. There is no installer, no pkg, no Homebrew cask to update.

## Preflight

1. Version is set in one place — `Info.plist`:

   ```bash
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist
   /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist
   ```

   `build.sh` and `package.sh` both read these, so the DMG name follows automatically. Bump build number every release, even for a rebuild of the same version.

2. `CHANGELOG.md` has an entry for the version. Write it for someone deciding whether to download, not for the commit log.
3. Working tree is clean, and `git status --short` shows no stray `.DS_Store`, `dist/`, `models/`, or `vendor/` (all ignored, but check).
4. Docs still match behaviour. The three that drift are `docs/USAGE.md` (shortcuts, settings), `README.md` (claims about privacy and model speed), and `docs/ARCHITECTURE.md` (file counts, pipeline).

## Build and package

```bash
rm -rf QuickFlow.app dist            # start from nothing
./Scripts/fetch-model.sh             # only if models/ is empty
./build.sh --universal
./package.sh
```

Expect `build.sh` to take a couple of minutes on a cold vendor tree and `package.sh` about a minute to compress 431 MB.

## Verify before publishing

```bash
lipo -info QuickFlow.app/Contents/MacOS/QuickFlow
codesign -dv --verbose=4 QuickFlow.app 2>&1 | grep -E 'flags|Identifier'
codesign -d --entitlements :- QuickFlow.app
otool -L QuickFlow.app/Contents/MacOS/QuickFlow | grep -icE 'cfnetwork|network|curl'   # 0

Q=QuickFlow.app/Contents/MacOS/QuickFlow
$Q --check
$Q --transcribe vendor/whisper.cpp/samples/jfk.wav
$Q --render-live /tmp/panel.png
```

Then install the DMG the way a user would — mount it, drag to Applications, eject, launch from Applications, approve both permissions, dictate one sentence into TextEdit. This catches the failure that matters and that a source-tree build hides: a copy that runs from the checkout but not from `/Applications` after quarantine.

Mount check without installing:

```bash
hdiutil attach dist/QuickFlow-3.0.dmg -mountpoint /tmp/qf_dmg_check -nobrowse
ls /tmp/qf_dmg_check
hdiutil detach /tmp/qf_dmg_check
```

## Tag and publish

```bash
V=3.0.0
git tag -a "v$V" -m "QuickFlow $V"
git push origin main --tags

gh release create "v$V" dist/QuickFlow-3.0.dmg dist/SHA256SUMS \
  --title "QuickFlow $V" \
  --notes-file /tmp/notes.md
```

Notes should lead with what changed for the person using it, then the install caveat, then the checksum. Keep the caveat in every release until the app is notarized:

> Ad-hoc signed, not notarized. On first launch, right-click QuickFlow → Open, or run `xattr -dr com.apple.quarantine /Applications/QuickFlow.app`. The DMG is built from this tag; verify it against `SHA256SUMS`.

## After publishing

- Download the DMG from the release page in a browser — this is the only way to catch a truncated upload or an asset attached to the wrong tag.
- Compare `shasum -a 256` with `SHA256SUMS` and with the value printed by `package.sh`.
- Confirm the release notes render, links resolve, and the docs links in the DMG Read Me still point at the repository.
- Announce, if at all, with the caveat about Gatekeeper — a "damaged app" report is the predictable consequence of leaving it out.

## If something is wrong

Do not edit or replace assets on a published release silently. Bump `CFBundleVersion`, rebuild, publish a new patch release, and if the old build is dangerous (data loss, wrong transcripts pasted without warning), mark the old one as a pre-release or delete it and say so in the new notes.

There is no auto-update mechanism, so users on an old version stay on it until they notice. That is a deliberate trade for having no networking code in the app.
