import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeys: HotKeyManager?
    private var recorder: AudioRecorder?
    private var engine: WhisperEngine?
    private var hud: HUDController?
    private var settingsWindow: SettingsWindowController?
    private var startItem: NSMenuItem?
    private var finishItem: NSMenuItem?
    private var copyItem: NSMenuItem?
    private var recentItem: NSMenuItem?
    private var welcomeWindow: WelcomeWindowController?
    private var micItem: NSMenuItem?
    private var axItem: NSMenuItem?
    private var liveItem: NSMenuItem?
    private var live: LiveTranscriber?

    private var targetApplication: NSRunningApplication?
    private var lastTranscript: String?
    private var isBusy = false
    private var accessibilityNoticeShown = false

    private let prefs = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ModelStore.prepareDirectories()
        if let iconPath = Bundle.main.path(forResource: "QuickFlow", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }

        hud = HUDController()
        buildStatusItem()
        registerHotKeys()
        requestFirstRunPermissions()
        prepareModel(openSettingsOnFailure: true)
        if !prefs.hasOnboarded {
            showWelcome()
        }
    }

    @objc private func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = WelcomeWindowController()
            welcomeWindow?.onClose = { [weak self] in
                NSApp.setActivationPolicy(.accessory)
                self?.welcomeWindow = nil
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.window?.makeKeyAndOrderFront(nil)
        NSLog("QuickFlow welcome shown frame=%@ visible=%d",
              NSStringFromRect(welcomeWindow?.window?.frame ?? .zero),
              welcomeWindow?.window?.isVisible == true ? 1 : 0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        recorder?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func modelSelectionChanged() {
        prepareModel(openSettingsOnFailure: false)
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "QuickFlow")
            button.image?.isTemplate = true
            button.toolTip = "QuickFlow — press ⌥⌘R to dictate"
        }

        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "QuickFlow", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "QuickFlow",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        header.isEnabled = false
        menu.addItem(header)

        let start = NSMenuItem(title: "Start Dictation", action: #selector(startDictation), keyEquivalent: "r")
        start.keyEquivalentModifierMask = [.option, .command]
        start.target = self
        menu.addItem(start)
        startItem = start

        let finish = NSMenuItem(title: "Finish and Transcribe", action: #selector(finishDictation), keyEquivalent: "t")
        finish.keyEquivalentModifierMask = [.option, .command]
        finish.target = self
        menu.addItem(finish)
        finishItem = finish

        let copyLast = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
        copyLast.target = self
        menu.addItem(copyLast)
        copyItem = copyLast

        let recent = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        recentMenu.delegate = self
        recent.submenu = recentMenu
        menu.addItem(recent)
        recentItem = recent

        let liveToggle = NSMenuItem(
            title: "Live Subtitles",
            action: #selector(toggleLiveSubtitles),
            keyEquivalent: ""
        )
        liveToggle.target = self
        menu.addItem(liveToggle)
        liveItem = liveToggle

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "About QuickFlow", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quickStart = NSMenuItem(title: "Quick Start…", action: #selector(showWelcome), keyEquivalent: "")
        quickStart.target = self
        menu.addItem(quickStart)

        let mic = NSMenuItem(title: "Microphone", action: #selector(openMicrophoneSettings), keyEquivalent: "")
        mic.target = self
        menu.addItem(mic)
        micItem = mic

        let ax = NSMenuItem(title: "Accessibility", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        axItem = ax

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === recentItem?.submenu {
            rebuildRecentMenu(menu)
            return
        }
        refreshMenuState()
    }

    private func refreshMenuState() {
        let recording = recorder?.isRecording ?? false
        startItem?.title = recording ? "Restart Dictation" : "Start Dictation"
        startItem?.isEnabled = !isBusy || recording
        finishItem?.isEnabled = recording
        copyItem?.isEnabled = lastTranscript != nil
        liveItem?.state = prefs.liveSubtitles ? .on : .off
        switch Permissions.microphone {
        case .granted:
            micItem?.title = "Microphone: allowed ✓"
            micItem?.isEnabled = false
        case .denied:
            micItem?.title = "Microphone: blocked — click to fix"
            micItem?.isEnabled = true
        case .undetermined:
            micItem?.title = "Microphone: not requested — click to fix"
            micItem?.isEnabled = true
        }
        if Permissions.accessibility {
            axItem?.title = "Accessibility: on ✓"
            axItem?.isEnabled = false
        } else {
            axItem?.title = "Accessibility: off — click to fix"
            axItem?.isEnabled = true
        }
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: recording ? "waveform.circle.fill" : "waveform",
                accessibilityDescription: "QuickFlow"
            )
            button.image?.isTemplate = true
        }
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        guard let manager = HotKeyManager() else { return }
        let modifiers = HotKeyManager.commandOption
        let startOK = manager.register(keyCode: 0x0F, modifiers: modifiers, id: 1) { [weak self] in
            self?.startDictation()
        }
        let stopOK = manager.register(keyCode: 0x11, modifiers: modifiers, id: 2) { [weak self] in
            self?.finishDictation()
        }
        NSLog("[QuickFlow] hotkeys start=\(startOK) stop=\(stopOK)")
        guard startOK || stopOK else {
            hud?.showMessage("⌥⌘R is taken by another app", error: true)
            return
        }
        hotKeys = manager
    }

    // MARK: - Permissions

    private func requestFirstRunPermissions() {
        if Permissions.microphone == .undetermined {
            Permissions.requestMicrophone { _ in }
        }
        let askedKey = "askedAccessibility"
        if !Permissions.accessibility, !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                Permissions.promptAccessibility()
            }
        }
    }

    @objc private func openMicrophoneSettings() {
        Permissions.open(.microphone)
    }

    @objc private func openAccessibilitySettings() {
        Permissions.promptAccessibility()
        Permissions.open(.accessibility)
    }

    // MARK: - Model

    private func prepareModel(openSettingsOnFailure: Bool) {
        guard let path = ModelStore.activeModelPath(preferred: prefs.modelPath) else {
            hud?.showMessage("No model installed", error: true)
            if openSettingsOnFailure {
                showSettings()
            }
            return
        }
        prefs.modelPath = path

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let loaded = try WhisperEngine(modelPath: path)
                loaded.warmUp()
                DispatchQueue.main.async {
                    self?.engine = loaded
                }
            } catch {
                DispatchQueue.main.async {
                    self?.engine = nil
                    self?.hud?.showMessage("Could not load model", error: true)
                    if openSettingsOnFailure {
                        self?.showSettings()
                    }
                }
            }
        }
    }

    // MARK: - Dictation

    @objc private func startDictation() {
        NSLog("[QuickFlow] startDictation called (busy=\(isBusy) recording=\(recorder?.isRecording ?? false))")
        guard !isBusy else { return }
        if recorder?.isRecording == true {
            finishDictation()
            return
        }

        targetApplication = NSWorkspace.shared.frontmostApplication
        ensureMicrophone { [weak self] in
            guard let self else { return }
            self.beginRecording()
        }
    }

    private func ensureMicrophone(_ completion: @escaping () -> Void) {
        switch Permissions.microphone {
        case .granted:
            completion()
        case .undetermined:
            Permissions.requestMicrophone { [weak self] granted in
                if granted {
                    completion()
                } else {
                    self?.presentMicrophoneAlert()
                }
            }
        case .denied:
            presentMicrophoneAlert()
        }
    }

    private func presentMicrophoneAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "QuickFlow needs microphone access"
        alert.informativeText = "Turn on QuickFlow under System Settings › Privacy & Security › Microphone, then press ⌥⌘R again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.open(.microphone)
        }
    }

    private func beginRecording() {
        guard let engine else {
            hud?.showMessage("Model still loading…", error: true)
            prepareModel(openSettingsOnFailure: false)
            return
        }

        let recorder = AudioRecorder()
        recorder.onLevel = { [weak self] level in
            self?.hud?.updateLevel(level)
        }
        recorder.onLimitReached = { [weak self] in
            self?.finishDictation()
        }
        recorder.onError = { [weak self] error in
            self?.hud?.showMessage(error.localizedDescription, error: true)
        }

        do {
            try recorder.start(deviceUID: prefs.inputDeviceUID)
        } catch {
            hud?.showMessage(error.localizedDescription, error: true)
            return
        }

        _ = engine
        self.recorder = recorder
        isBusy = true
        playCue("Tink")
        hud?.showListening()
        startLiveSubtitles(for: recorder)
        refreshMenuState()
        // Escape aborts the take without transcribing, so a mis-hit never costs you a sentence.
        hotKeys?.register(keyCode: 0x35, modifiers: 0, id: 3) { [weak self] in
            self?.cancelDictation()
        }
    }

    // MARK: - Live subtitles

    @objc private func toggleLiveSubtitles() {
        prefs.liveSubtitles.toggle()
        refreshMenuState()
        if prefs.liveSubtitles {
            if let recorder, recorder.isRecording {
                startLiveSubtitles(for: recorder)
            }
        } else {
            stopLiveSubtitles()
        }
    }

    private func startLiveSubtitles(for recorder: AudioRecorder) {
        guard prefs.liveSubtitles, let engine else { return }
        let transcriber = live ?? LiveTranscriber(engine: engine, language: prefs.language)
        transcriber.onUpdate = { [weak self] text in
            self?.hud?.setTranscript(text)
        }
        transcriber.start()
        live = transcriber
        recorder.onSamples = { [weak transcriber] chunk in
            transcriber?.append(chunk)
        }
    }

    private func stopLiveSubtitles(keepPreview: Bool = false) {
        recorder?.onSamples = nil
        live?.stop()
        live = nil
        if !keepPreview {
            hud?.clearTranscript()
        }
    }

    @objc private func cancelDictation() {
        guard let recorder, recorder.isRecording else { return }
        hotKeys?.unregister(id: 3)
        stopLiveSubtitles()
        recorder.cancel()
        self.recorder = nil
        isBusy = false
        hotKeys?.unregister(id: 3)
        playCue("Basso")
        hud?.showMessage("Cancelled")
        refreshMenuState()
    }

    @objc private func finishDictation() {
        guard let recorder, recorder.isRecording else { return }
        hotKeys?.unregister(id: 3)
        stopLiveSubtitles(keepPreview: true)
        let recording = recorder.stop()
        self.recorder = nil
        playCue("Pop")
        refreshMenuState()

        guard let recording, recording.duration >= 0.4 else {
            hud?.showMessage("Too short", error: false)
            isBusy = false
            return
        }
        guard !recording.isSilent else {
            try? FileManager.default.removeItem(at: recording.url)
            hud?.showMessage("Didn't catch that", error: false)
            isBusy = false
            return
        }

        hud?.showWorking()

        let style = TextCleaner.style(for: targetApplication?.bundleIdentifier)
        let language = prefs.language
        let prompt = prefs.vocabularyPrompt
        let smart = prefs.smartFormatting

        guard let engine else {
            hud?.showMessage("Model not ready", error: true)
            isBusy = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? FileManager.default.removeItem(at: recording.url) }
            guard let self else { return }
            do {
                var transcript = try engine.transcribe(
                    url: recording.url,
                    language: language,
                    prompt: prompt
                ).text
                if smart {
                    transcript = SmartFormatter.format(transcript, style: style)
                }
                guard !transcript.isEmpty else {
                    DispatchQueue.main.async {
                        self.isBusy = false
                        self.hud?.showMessage("Didn't catch that", error: false)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.deliver(transcript)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.hud?.showMessage(error.localizedDescription, error: true)
                }
            }
        }
    }

    private func deliver(_ text: String) {
        lastTranscript = text
        remember(text)
        var pasted = false
        if prefs.autoPaste {
            pasted = TextInjector.paste(text, restoreClipboard: prefs.restoreClipboard)
        } else {
            TextInjector.copy(text)
        }
        isBusy = false
        refreshMenuState()

        if pasted {
            hud?.showMessage("Done")
        } else if prefs.autoPaste {
            hud?.showMessage("Copied — enable auto-paste")
            if !accessibilityNoticeShown {
                accessibilityNoticeShown = true
                presentAccessibilityNotice()
            }
        } else {
            hud?.showMessage("Copied")
        }
    }

    private func presentAccessibilityNotice() {
        let alert = NSAlert()
        alert.messageText = "Your transcript is copied"
        alert.informativeText = "QuickFlow needs Accessibility access to paste for you. Until then it copies the text so you can press ⌘V yourself."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.promptAccessibility()
            Permissions.open(.accessibility)
        }
    }

    private func playCue(_ name: String) {
        guard prefs.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    @objc private func copyLastTranscript() {
        guard let lastTranscript else { return }
        TextInjector.copy(lastTranscript)
        hud?.showMessage("Copied")
    }

    // MARK: - Recents

    private var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentTranscripts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentTranscripts") }
    }

    private func remember(_ text: String) {
        var items = recent.filter { $0 != text }
        items.insert(text, at: 0)
        recent = Array(items.prefix(10))
    }

    private func rebuildRecentMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = recent
        guard !items.isEmpty else {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for (index, text) in items.enumerated() {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let title = flat.count > 48 ? String(flat.prefix(48)) + "…" : flat
            let item = NSMenuItem(title: title, action: #selector(copyRecent(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = text
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Recents", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        let items = recent
        guard sender.tag >= 0, sender.tag < items.count else { return }
        TextInjector.copy(items[sender.tag])
        hud?.showMessage("Copied")
    }

    @objc private func clearRecent() {
        recent = []
        hud?.showMessage("Cleared")
    }

    // MARK: - Windows

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(appDelegate: self)
        }
        settingsWindow?.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "QuickFlow",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: "On-device dictation powered by whisper.cpp.\nNothing you say leaves your Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
