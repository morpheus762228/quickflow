# QuickFlow — "Download & Run" Release Checklist

Goal: a stranger on any Mac (Apple Silicon or Intel, macOS 13+) downloads one file from
GitHub, drags it to Applications, grants two permissions, and it works. No Python, no
Homebrew, no Xcode, no terminal.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[?]` needs a decision

---

## Audit — current state (verified)

| Item | State |
|---|---|
| Build | `./build.sh` succeeds; app is 240 KB + external Python runtime |
| Architecture | arm64 only (`Mach-O thin`) — will not launch on Intel Macs |
| Signature | ad-hoc, linker-signed, no Team ID — Gatekeeper blocks on other Macs |
| Notarization | impossible today — 0 valid signing identities |
| Python | hardcoded `/usr/bin/python3` (CLT shim on a fresh Mac → install prompt/failure) |
| Whisper | external `openai-whisper` + torch installed per-user; model in `~/.cache/whisper` (461 MB) |
| ffmpeg | installed and required by setup, but the live recording path (Swift) never uses it |
| Repo | **private**, 1 commit, no tags, no releases, no CI |
| README | clone URL points at `github.com/jameslopez/quickflow` (wrong owner) |
| Icon | none (menu bar shows emoji) |
| Baseline test | `BatchASR('tiny')` transcribed a 11 s sample in 2.0 s — pipeline is functional on this Mac |

### Bugs found while reading the code

- [ ] `backend/asr/streamer.py` uses `sys.stderr` but never imports `sys` → NameError on the whisper-missing path.
- [ ] `BatchASR.transcribe_file` has a 60 s timeout. First run downloads a 75–466 MB model → guaranteed timeout, uncaught exception, silent failure.
- [ ] `server.py:185` calls `ctx.detect_style(ctx)`; the method lives on `ContextInjector`, not `ScreenContext`. Dead today (no LLM configured), crashes when one is.
- [ ] `server.py` still contains the ffmpeg recording path and the BlackHole-prone mic index logic, unused by the app.
- [ ] Swift never checks Accessibility (`AXIsProcessTrusted`) before pasting; failures are silent.
- [ ] `NSAccessibilityUsageDescription` is not a real Info.plist key — permissions are system-managed, not described here.
- [ ] Every transcription pays a fresh Python + torch import + model load (startup latency).
- [ ] `Info.plist` is not bound into the signature; version is duplicated in code and README.
- [ ] `build.sh` copies `__pycache__` into the bundle.
- [ ] `setup.sh` uses `pip3 install --user`, which fails under PEP 668 on modern Python, and installs ffmpeg needlessly.

---

## Phase 0 — Decisions + repo foundation

- [?] **D1. Engine strategy** (see "Decision notes" below)
- [?] **D2. Signing** — Apple Developer Program ($99/yr) or ad-hoc + quarantine instructions
- [?] **D3. Model delivery** — bundle vs first-run download
- [?] **D4. Repo visibility** — make public (required for "download off GitHub")
- [ ] Fix README clone URL and requirements section
- [ ] Add app icon (`.icns`, 1024px source, `CFBundleIconFile`)
- [ ] Single source of truth for version (`VERSION`), bump to `1.0.0`
- [ ] Add `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`
- [ ] Add `.github/ISSUE_TEMPLATE/bug.yml`, `feature.yml`, PR template
- [ ] Add CI: build on push, release on tag
- [ ] Add `.github/workflows/ci.yml` (compile + shellcheck + unit tests)
- [ ] Stop shipping build artifacts; confirm `.gitignore`

## Phase 1 — Make the app self-contained (the real work)

- [ ] Remove the Python dependency from the shipped app
  - [ ] Port `RuleBasedCleaner` → Swift (regex rules)
  - [ ] Port context detection → `NSWorkspace` + Accessibility API (drop osascript)
  - [ ] Port paste → `CGEvent` (drop osascript / System Events)
  - [ ] Port correction store → SQLite in Application Support (or defer to v1.1)
- [ ] Add whisper.cpp via SPM, Metal-accelerated, model kept resident in memory
- [ ] Model management
  - [ ] Bundle or download `ggml-base.en.bin` (142 MB) with SHA-256 verification
  - [ ] Optional in-app download of `small.en` (466 MB) / `medium.en` (1.5 GB)
  - [ ] Progress UI, resumable download, disk-space check
  - [ ] Store models in `~/Library/Application Support/QuickFlow/models/`
- [ ] Universal binary: `arm64` + `x86_64`, `LSMinimumSystemVersion 13.0`
- [ ] Replace `/tmp` audio + PID files with Application Support / `FileManager.temporaryDirectory`
- [ ] Fix all bugs listed in the audit above
- [ ] Unit tests for cleaner, context style mapping, model path resolution

## Phase 2 — First-run and permissions UX

- [ ] Onboarding window on first launch: what it does, the two shortcuts, next step
- [ ] Permission center with live status: Microphone, Accessibility, Notifications
  - [ ] Request mic via `AVCaptureDevice.requestAccess`
  - [ ] Request Accessibility via `AXIsProcessTrustedWithOptions` + deep link to the pane
  - [ ] Recheck on app activation, not just once
- [ ] Microphone picker (fixes BlackHole/virtual-device capture generically)
- [ ] Hotkey customization + conflict detection
- [ ] Launch at login toggle (`SMAppService.mainApp`)
- [ ] Settings window: model, language, paste vs clipboard-only, sounds, clipboard restore
- [ ] Recording HUD (floating pill with level meter) + start/stop sounds
- [ ] Paste failure handling: keep text on clipboard, notify, never lose the transcript
- [ ] Secure-input detection (do not attempt paste into password fields)
- [ ] Max recording length + idle auto-stop
- [ ] In-app log viewer or "Copy diagnostics" button

## Phase 3 — Packaging, signing, notarization

- [ ] `QuickFlow.entitlements`: `com.apple.security.device.audio-input` (+ `automation.apple-events` only if osascript remains)
- [ ] Hardened runtime enabled (`--options runtime`)
- [ ] Developer ID Application certificate installed (D2)
- [ ] `scripts/release.sh`: clean build → universal → sign → DMG → notarize → staple → checksums
- [ ] DMG with drag-to-Applications layout and volume icon
- [ ] Verify: `codesign --verify --deep --strict`, `spctl -a -vvv`, `stapler validate`
- [ ] Test on a clean macOS VM (no dev tools) and on Intel hardware or Rosetta
- [ ] Test the "downloaded from the internet" path (quarantine bit set)
- [ ] Record Gatekeeper behavior for the ad-hoc fallback, if that path is chosen

## Phase 4 — Release automation

- [ ] `.github/workflows/release.yml` on `v*` tag: build → sign → notarize → staple → DMG/ZIP → SHA256SUMS → attach
- [ ] Secrets: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`
- [ ] Universal build in CI (two `swiftc -target` slices + `lipo`, or `CMAKE_OSX_ARCHITECTURES`)
- [ ] Tag `v1.0.0` and publish release notes
- [ ] Homebrew cask (`brew install --cask quickflow`) — optional
- [ ] Sparkle auto-update + appcast — optional, needs D2
- [ ] Release badge + download link in README

## Phase 5 — Docs and launch polish

- [ ] README: one-line install, demo GIF, screenshots, permissions, troubleshooting
- [ ] FAQ: "app is damaged / cannot be opened", model sizes, Intel support, privacy
- [ ] Privacy statement: fully local, no telemetry, no network except model download
- [ ] Uninstall instructions (app + Application Support)
- [ ] Architecture doc updated to the new engine
- [ ] Optional landing page

---

## Decision notes

### D1. Engine — recommended: native Swift + whisper.cpp

| | Native (whisper.cpp) | Bundle Python runtime |
|---|---|---|
| Download size | ~20 MB app + 142 MB model | ~400 MB–2 GB |
| Cold start | instant, model resident | 2–5 s Python/torch import per run |
| Arch support | universal, easy | per-arch builds, PyInstaller is not universal |
| Signing | one binary | every embedded `.so`/`.dylib` must be signed |
| Risk | rewrite of ~600 LOC of backend | keeps existing code |
| Deps | none | frozen runtime, still fragile |

Recommendation: native. The Python backend exists only for Whisper, regex cleanup, and
osascript glue; none of that needs Python. Keep `backend/` in the repo for power users
(`QUICKFLOW_BACKEND=python`) or move it to `legacy/` for v1.

### D2. Signing

- **Developer ID ($99/yr)** — app opens with no warnings, permissions stay granted across
  updates, Sparkle works. This is the only true "ready to use" path.
- **Ad-hoc (free)** — every user must right-click → Open or run
  `xattr -dr com.apple.quarantine /Applications/QuickFlow.app`. The signature changes on
  every build, so macOS treats each update as a new app: mic and Accessibility must be
  re-granted each time.

### D3. Model

Bundle `base.en` (142 MB) for offline first-run, offer `small.en` as an in-app download.
Bundle `small.en` (466 MB) instead if accuracy matters more than download size.
