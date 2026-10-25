import AppKit

/// First-run window: explains the two shortcuts, asks for the two permissions
/// that matter, and then gets out of the way.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let micButton = NSButton(title: "Enable Microphone", target: nil, action: nil)
    private let axButton = NSButton(title: "Open Accessibility…", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.center()
        self.init(window: window)
        window.delegate = self
        buildContent()
        refreshStatus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatus),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    private func buildContent() {
        guard let window, let content = window.contentView else { return }

        let iconView = NSImageView()
        if let path = Bundle.main.path(forResource: "QuickFlow", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            iconView.image = image
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 76).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let title = NSTextField(labelWithString: "Welcome to QuickFlow")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Private dictation that stays on this Mac.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let steps = NSStackView(views: [
            step(symbol: "mic.fill",
                 title: "Press ⌥⌘R and talk",
                 detail: "⌥⌘T stops and transcribes. Esc throws the take away."),
            step(symbol: "keyboard",
                 title: "Text lands where you're typing",
                 detail: "QuickFlow pastes for you once Accessibility is allowed."),
            step(symbol: "wand.and.stars",
                 title: "Speak naturally",
                 detail: "Say “period”, “comma”, “new paragraph”. Fillers disappear.")
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 16

        micButton.target = self
        micButton.action = #selector(enableMicrophone)
        micButton.bezelStyle = .rounded
        micButton.controlSize = .large

        axButton.target = self
        axButton.action = #selector(openAccessibility)
        axButton.bezelStyle = .rounded
        axButton.controlSize = .large

        let startButton = NSButton(title: "Start Using QuickFlow", target: self, action: #selector(finish))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [axButton, micButton, startButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .center

        let stack = NSStackView(views: [iconView, title, subtitle, steps, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(4, after: iconView)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(22, after: steps)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
    }

    private func step(symbol: String, title: String, detail: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: detail)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 330

        let text = NSStackView(views: [heading, body])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        return row
    }

    @objc private func refreshStatus() {
        let mic: String
        switch Permissions.microphone {
        case .granted:
            mic = "Microphone ready"
            micButton.title = "Microphone Enabled"
            micButton.isEnabled = false
        case .denied:
            mic = "Microphone blocked — enable it in System Settings"
            micButton.title = "Open Microphone Settings…"
            micButton.isEnabled = true
        case .undetermined:
            mic = "Microphone not requested yet"
            micButton.title = "Enable Microphone"
            micButton.isEnabled = true
        }
        let ax = Permissions.accessibility ? "Accessibility ready" : "Accessibility not granted"
        statusLabel.stringValue = "\(mic)  ·  \(ax)"
        axButton.title = Permissions.accessibility ? "Accessibility Enabled" : "Open Accessibility…"
        axButton.isEnabled = !Permissions.accessibility
    }

    @objc private func enableMicrophone() {
        switch Permissions.microphone {
        case .undetermined:
            Permissions.requestMicrophone { _ in
                self.refreshStatus()
            }
        case .denied:
            Permissions.open(.microphone)
        case .granted:
            break
        }
    }

    @objc private func openAccessibility() {
        Permissions.promptAccessibility()
        Permissions.open(.accessibility)
    }

    @objc private func finish() {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        Preferences.shared.hasOnboarded = true
        onClose?()
    }
}
