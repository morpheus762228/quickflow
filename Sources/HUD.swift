import AppKit

final class LevelBarsView: NSView {
    var level: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    private let factors: [CGFloat] = [0.5, 0.78, 1.0, 0.72, 0.46]
    private let barWidth: CGFloat = 4
    private let gap: CGFloat = 3

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let totalWidth = CGFloat(factors.count) * barWidth + CGFloat(factors.count - 1) * gap
        var x = (bounds.width - totalWidth) / 2
        let clamped = max(0.06, min(1, level))
        NSColor.white.withAlphaComponent(0.92).setFill()

        for factor in factors {
            let height = max(3, bounds.height * (0.16 + 0.84 * clamped * factor))
            let rect = NSRect(
                x: x,
                y: bounds.midY - height / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}

private final class HUDWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDController {
    private let panel = HUDWindow()
    private let bars = LevelBarsView()
    private let spinner = NSProgressIndicator()
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var subtitleHeight: NSLayoutConstraint?
    private var timer: Timer?
    private var startedAt: Date?
    private var hideWork: DispatchWorkItem?

    private enum Mode {
        case listening
        case working
        case message
    }

    init() {
        build()
    }

    private func build() {
        guard let content = panel.contentView else { return }
        content.wantsLayer = true

        let effect = NSVisualEffectView(frame: content.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        content.addSubview(effect)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dot)

        bars.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(bars)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(spinner)

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.88)
        subtitle.lineBreakMode = .byTruncatingHead
        subtitle.maximumNumberOfLines = 4
        subtitle.cell?.wraps = true
        subtitle.cell?.isScrollable = false
        subtitle.preferredMaxLayoutWidth = 408
        subtitle.isHidden = true
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(subtitle)

        let subtitleHeight = subtitle.heightAnchor.constraint(equalToConstant: 0)
        self.subtitleHeight = subtitleHeight

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            dot.topAnchor.constraint(equalTo: effect.topAnchor, constant: 24),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            bars.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 11),
            bars.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            bars.widthAnchor.constraint(equalToConstant: 34),
            bars.heightAnchor.constraint(equalToConstant: 22),

            spinner.centerXAnchor.constraint(equalTo: bars.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: dot.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: bars.trailingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: dot.centerYAnchor),

            subtitle.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            subtitle.topAnchor.constraint(equalTo: effect.topAnchor, constant: 48),
            subtitleHeight
        ])

        label.stringValue = "0:00"
    }

    // MARK: - Live subtitles

    /// Show the in-progress transcript under the timer. Grows the panel downwards,
    /// keeping the bottom edge where it is so the pill does not jump around.
    func setTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearTranscript()
            return
        }
        subtitle.stringValue = trimmed
        subtitle.isHidden = false
        let measured = subtitle.sizeThatFits(NSSize(width: 408, height: 400)).height
        let height = min(76, max(17, ceil(measured)))
        subtitleHeight?.constant = height
        resize(width: 440, height: 60 + height)
    }

    func clearTranscript() {
        subtitle.stringValue = ""
        subtitle.isHidden = true
        subtitleHeight?.constant = 0
        resize(width: 240, height: 56)
    }

    /// Developer aid: render the panel to a PNG without screen-recording permission,
    /// so subtitle layout can be checked offscreen.
    func renderSnapshot(to path: String) -> Bool {
        panel.setFrame(NSRect(origin: panel.frame.origin, size: panel.frame.size), display: false)
        guard let view = panel.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private func resize(width: CGFloat, height: CGFloat) {
        var frame = panel.frame
        guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else { return }
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true)
        if panel.isVisible { position() }
    }

    func showListening() {
        hideWork?.cancel()
        startedAt = Date()
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        bars.isHidden = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        clearTranscript()
        setLabel("0:00")
        startTimer()
        present()
    }

    func updateLevel(_ level: Float) {
        bars.level = CGFloat(level)
    }

    func showWorking() {
        hideWork?.cancel()
        stopTimer()
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        bars.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
        setLabel("Transcribing…")
        present()
    }

    func showMessage(_ text: String, error: Bool = false) {
        hideWork?.cancel()
        stopTimer()
        dot.layer?.backgroundColor = (error ? NSColor.systemRed : NSColor.systemGreen).cgColor
        bars.isHidden = true
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        clearTranscript()
        setLabel(text)
        present()
        hide(after: error ? 2.6 : 1.5)
    }

    func hideNow() {
        hideWork?.cancel()
        stopTimer()
        clearTranscript()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func setLabel(_ text: String) {
        label.stringValue = text
        label.font = text.contains(":") && text.count <= 5
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            : .systemFont(ofSize: 12, weight: .medium)
    }

    private func present() {
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hide(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            self.label.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        ))
    }
}
