import AppKit
import ServiceManagement

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class StatusDot: NSView {
    var color: NSColor = .systemGray {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

private final class CardView: NSView {
    let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func addRow(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let prefs = Preferences.shared
    private weak var appDelegate: AppDelegate?

    private let micDot = StatusDot()
    private let axDot = StatusDot()
    private let micStatus = NSTextField(labelWithString: "")
    private let axStatus = NSTextField(labelWithString: "")
    private let micButton = NSButton(title: "Grant", target: nil, action: nil)
    private let axButton = NSButton(title: "Grant", target: nil, action: nil)

    private let devicePopup = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let vocabularyField = NSTextField()
    private let autoPasteSwitch = NSSwitch()
    private let restoreSwitch = NSSwitch()
    private let soundsSwitch = NSSwitch()
    private let formattingSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()

    private var refreshTimer: Timer?
    private var models: [ModelInfo] = []

    private static let languages: [(String, String)] = [
        ("auto", "Detect automatically"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("ru", "Russian"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("uk", "Ukrainian")
    ]

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickFlow Settings"
        window.minSize = NSSize(width: 520, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        refreshTimer?.invalidate()
    }

    func show() {
        reload()
        refreshPermissions()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func buildInterface() {
        guard let window, let content = window.contentView else { return }

        devicePopup.target = self
        devicePopup.action = #selector(deviceChanged)
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            root.topAnchor.constraint(equalTo: document.topAnchor),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        func pin(_ view: NSView) {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }

        let header = buildHeader()
        root.addArrangedSubview(header)
        pin(header)

        let gettingStarted = buildGettingStarted()
        root.addArrangedSubview(gettingStarted)
        pin(gettingStarted)

        let permissionsTitle = sectionTitle("Permissions")
        root.addArrangedSubview(permissionsTitle)

        let permissions = buildPermissionsCard()
        root.addArrangedSubview(permissions)
        pin(permissions)

        let dictationTitle = sectionTitle("Dictation")
        root.addArrangedSubview(dictationTitle)

        let dictation = buildDictationCard()
        root.addArrangedSubview(dictation)
        pin(dictation)

        let modelTitle = sectionTitle("Model & Language")
        root.addArrangedSubview(modelTitle)

        let model = buildModelCard()
        root.addArrangedSubview(model)
        pin(model)

        let behaviourTitle = sectionTitle("Behaviour")
        root.addArrangedSubview(behaviourTitle)

        let behaviour = buildBehaviourCard()
        root.addArrangedSubview(behaviour)
        pin(behaviour)

        let footer = buildFooter()
        root.addArrangedSubview(footer)
        pin(footer)
    }

    private func buildHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = NSTextField(labelWithString: "QuickFlow")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Private, on-device dictation for macOS · \(AppInfo.version)")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [icon, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func buildGettingStarted() -> NSView {
        let card = CardView()

        let heading = NSTextField(labelWithString: "Get started in three steps")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        card.addRow(heading)

        let steps = [
            "Grant Microphone access so QuickFlow can hear you.",
            "Grant Accessibility access so it can paste into the app you are using.",
            "Press ⌥⌘R anywhere to start dictating, ⌥⌘T to finish."
        ]
        for (index, step) in steps.enumerated() {
            let number = NSTextField(labelWithString: "\(index + 1).")
            number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            number.textColor = .controlAccentColor
            number.setContentHuggingPriority(.required, for: .horizontal)

            let text = NSTextField(wrappingLabelWithString: step)
            text.font = .systemFont(ofSize: 12)
            text.textColor = .secondaryLabelColor

            let row = NSStackView(views: [number, text])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            card.addRow(row)
        }
        return card
    }

    private func buildPermissionsCard() -> NSView {
        let card = CardView()
        card.addRow(permissionRow(
            title: "Microphone",
            dot: micDot,
            status: micStatus,
            button: micButton,
            action: #selector(microphoneAction)
        ))
        card.addRow(permissionRow(
            title: "Accessibility",
            dot: axDot,
            status: axStatus,
            button: axButton,
            action: #selector(accessibilityAction)
        ))

        let note = NSTextField(wrappingLabelWithString: "Accessibility is only used to press ⌘V for you. QuickFlow never reads the contents of other apps.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        card.addRow(note)
        return card
    }

    private func permissionRow(
        title: String,
        dot: StatusDot,
        status: NSTextField,
        button: NSButton,
        action: Selector
    ) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .medium)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .right

        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let row = NSStackView(views: [dot, name, spacer, status, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func buildDictationCard() -> NSView {
        let card = CardView()
        card.addRow(formRow(title: "Input", control: devicePopup))

        let note = NSTextField(wrappingLabelWithString: "QuickFlow prefers your built-in microphone and skips virtual audio devices when possible.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        card.addRow(note)
        return card
    }

    private func buildModelCard() -> NSView {
        let card = CardView()
        card.addRow(formRow(title: "Model", control: modelPopup))
        card.addRow(formRow(title: "Language", control: languagePopup))

        let vocabularyLabel = NSTextField(labelWithString: "Vocabulary")
        vocabularyLabel.font = .systemFont(ofSize: 13)
        vocabularyLabel.textColor = .secondaryLabelColor
        vocabularyLabel.alignment = .right
        vocabularyLabel.translatesAutoresizingMaskIntoConstraints = false
        vocabularyLabel.widthAnchor.constraint(equalToConstant: 104).isActive = true

        vocabularyField.placeholderString = "Names, acronyms, jargon"
        vocabularyField.font = .systemFont(ofSize: 13)
        vocabularyField.delegate = self
        vocabularyField.translatesAutoresizingMaskIntoConstraints = false
        vocabularyField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        vocabularyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let vocabularyRow = NSStackView(views: [vocabularyLabel, vocabularyField])
        vocabularyRow.orientation = .horizontal
        vocabularyRow.alignment = .centerY
        vocabularyRow.spacing = 10
        card.addRow(vocabularyRow)

        let vocabularyNote = NSTextField(wrappingLabelWithString: "Helps with unusual names and technical terms. Improves spelling, not speed.")
        vocabularyNote.font = .systemFont(ofSize: 11)
        vocabularyNote.textColor = .tertiaryLabelColor
        card.addRow(vocabularyNote)

        let folderButton = NSButton(title: "Reveal Models Folder", target: self, action: #selector(revealModels))
        folderButton.bezelStyle = .inline
        folderButton.isBordered = false
        folderButton.contentTintColor = .controlAccentColor
        folderButton.font = .systemFont(ofSize: 11)
        folderButton.setContentHuggingPriority(.required, for: .horizontal)
        card.addRow(folderButton)
        return card
    }

    private func buildBehaviourCard() -> NSView {
        let card = CardView()

        configureSwitch(autoPasteSwitch, action: #selector(autoPasteChanged))
        card.addRow(toggleRow(
            title: "Paste automatically",
            note: "Inserts the transcript into the app you were using. Turn off to copy instead.",
            toggle: autoPasteSwitch
        ))

        configureSwitch(restoreSwitch, action: #selector(restoreChanged))
        card.addRow(toggleRow(
            title: "Keep my clipboard",
            note: "Restores what you had copied before dictating.",
            toggle: restoreSwitch
        ))

        configureSwitch(formattingSwitch, action: #selector(formattingChanged))
        card.addRow(toggleRow(
            title: "Smart formatting",
            note: "Removes filler words, fixes capitals, and adapts to the app.",
            toggle: formattingSwitch
        ))

        configureSwitch(soundsSwitch, action: #selector(soundsChanged))
        card.addRow(toggleRow(
            title: "Sound cues",
            note: "A short tone when recording starts and stops.",
            toggle: soundsSwitch
        ))

        configureSwitch(loginSwitch, action: #selector(loginChanged))
        card.addRow(toggleRow(
            title: "Launch at login",
            note: "Keeps QuickFlow ready in the menu bar.",
            toggle: loginSwitch
        ))
        return card
    }

    private func buildFooter() -> NSView {
        let check = NSButton(title: "Check Permissions", target: self, action: #selector(checkPermissions))
        check.bezelStyle = .rounded

        let done = NSButton(title: "Done", target: self, action: #selector(closeSettings))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let quitNote = NSTextField(labelWithString: "QuickFlow lives in your menu bar.")
        quitNote.font = .systemFont(ofSize: 11)
        quitNote.textColor = .tertiaryLabelColor

        let buttons = NSStackView(views: [quitNote, spacer, check, done])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        return buttons
    }

    private func formRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 104).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 300).isActive = true
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func toggleRow(title: String, note: String, toggle: NSSwitch) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)

        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .tertiaryLabelColor

        let textStack = NSStackView(views: [titleLabel, noteLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [toggle, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func configureSwitch(_ toggle: NSSwitch, action: Selector) {
        toggle.target = self
        toggle.action = action
        toggle.state = .off
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func reload() {
        reloadDevices()
        reloadModels()
        reloadLanguages()
        vocabularyField.stringValue = prefs.vocabulary
        autoPasteSwitch.state = prefs.autoPaste ? .on : .off
        restoreSwitch.state = prefs.restoreClipboard ? .on : .off
        soundsSwitch.state = prefs.playSounds ? .on : .off
        formattingSwitch.state = prefs.smartFormatting ? .on : .off
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshPermissions()
    }

    private func reloadDevices() {
        devicePopup.removeAllItems()
        devicePopup.addItem(withTitle: "System Default")
        devicePopup.lastItem?.representedObject = ""

        for device in AudioDevices.allInputs() {
            devicePopup.addItem(withTitle: device.displayName)
            devicePopup.lastItem?.representedObject = device.uid
        }

        let selected = prefs.inputDeviceUID
        if let index = devicePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) {
            devicePopup.selectItem(at: index)
        } else {
            devicePopup.selectItem(at: 0)
        }
    }

    private func reloadModels() {
        models = ModelStore.availableModels()
        modelPopup.removeAllItems()

        if models.isEmpty {
            modelPopup.addItem(withTitle: "No model installed")
            modelPopup.isEnabled = false
            return
        }

        modelPopup.isEnabled = true
        let active = ModelStore.activeModelPath(preferred: prefs.modelPath)
        for model in models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.path
            if let item = modelPopup.lastItem, !model.isBundled {
                item.toolTip = model.path
            }
        }
        if let index = modelPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == active }) {
            modelPopup.selectItem(at: index)
        }
    }

    private func reloadLanguages() {
        languagePopup.removeAllItems()
        for (code, name) in Self.languages {
            languagePopup.addItem(withTitle: name)
            languagePopup.lastItem?.representedObject = code
        }
        if let index = languagePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == prefs.language }) {
            languagePopup.selectItem(at: index)
        } else {
            languagePopup.selectItem(at: 0)
        }
    }

    private func refreshPermissions() {
        switch Permissions.microphone {
        case .granted:
            micDot.color = .systemGreen
            micStatus.stringValue = "Granted"
            micButton.title = "Open Settings"
        case .denied:
            micDot.color = .systemRed
            micStatus.stringValue = "Denied"
            micButton.title = "Open Settings"
        case .undetermined:
            micDot.color = .systemOrange
            micStatus.stringValue = "Not granted"
            micButton.title = "Grant"
        }

        if Permissions.accessibility {
            axDot.color = .systemGreen
            axStatus.stringValue = "Granted"
            axButton.title = "Open Settings"
        } else {
            axDot.color = .systemOrange
            axStatus.stringValue = "Required for auto-paste"
            axButton.title = "Grant"
        }
    }

    @objc private func microphoneAction() {
        switch Permissions.microphone {
        case .undetermined:
            Permissions.requestMicrophone { [weak self] granted in
                if !granted {
                    Permissions.open(.microphone)
                }
                self?.refreshPermissions()
            }
        case .granted, .denied:
            Permissions.open(.microphone)
        }
    }

    @objc private func accessibilityAction() {
        if Permissions.accessibility {
            Permissions.open(.accessibility)
        } else {
            Permissions.promptAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Permissions.open(.accessibility)
            }
        }
    }

    @objc private func checkPermissions() {
        refreshPermissions()
        reloadDevices()
        if !Permissions.accessibility && Permissions.microphone == .granted {
            Permissions.promptAccessibility()
        }
    }

    @objc private func closeSettings() {
        window?.close()
    }

    @objc private func revealModels() {
        ModelStore.prepareDirectories()
        NSWorkspace.shared.open(ModelStore.modelsDirectory)
    }

    @objc private func autoPasteChanged() {
        prefs.autoPaste = autoPasteSwitch.state == .on
        if prefs.autoPaste && !Permissions.accessibility {
            Permissions.promptAccessibility()
        }
    }

    @objc private func restoreChanged() {
        prefs.restoreClipboard = restoreSwitch.state == .on
    }

    @objc private func formattingChanged() {
        prefs.smartFormatting = formattingSwitch.state == .on
    }

    @objc private func soundsChanged() {
        prefs.playSounds = soundsSwitch.state == .on
    }

    @objc private func loginChanged() {
        do {
            if loginSwitch.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginSwitch.state = loginSwitch.state == .on ? .off : .on
            let alert = NSAlert()
            alert.messageText = "Could not update login item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func deviceChanged() {
        prefs.inputDeviceUID = (devicePopup.selectedItem?.representedObject as? String) ?? ""
    }

    @objc private func modelChanged() {
        guard let path = modelPopup.selectedItem?.representedObject as? String else { return }
        prefs.modelPath = path
        appDelegate?.modelSelectionChanged()
    }

    @objc private func languageChanged() {
        prefs.language = (languagePopup.selectedItem?.representedObject as? String) ?? "en"
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        prefs.vocabulary = vocabularyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
