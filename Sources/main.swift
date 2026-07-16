import Cocoa
import Carbon
import UserNotifications
import AVFoundation

// MARK: - Native Audio Recorder
class NativeRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private let outputURL = URL(fileURLWithPath: "/tmp/quickflow-orchestrator.wav")
    private(set) var isRecording = false
    
    func start() -> Bool {
        guard !isRecording else { return false }
        
        // Clean up old file
        try? FileManager.default.removeItem(at: outputURL)
        
        // 16kHz mono PCM for whisper
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        
        do {
            recorder = try AVAudioRecorder(url: outputURL, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            let ok = recorder?.record() ?? false
            isRecording = ok
            return ok
        } catch {
            print("[NativeRecorder] Error: \(error)")
            return false
        }
    }
    
    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
    }
}

// MARK: - Global Hotkey Manager
class HotkeyManager {
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    
    enum Action: UInt32 { case startRecording = 1, stopTranscribe = 2 }
    var onHotkey: ((Action) -> Void)?
    
    func register() {
        registerHotkey(id: .startRecording, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | cmdKey))
        registerHotkey(id: .stopTranscribe, keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | cmdKey))
        var gEventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return -1 }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = Action(rawValue: id.id) { DispatchQueue.main.async { mgr.onHotkey?(action) } }
            return noErr
        }, 1, &gEventType, selfPtr, &eventHandler)
    }
    
    private func registerHotkey(id: Action, keyCode: UInt32, modifiers: UInt32) {
        let hid = EventHotKeyID(signature: OSType(0x51464C4F), id: id.rawValue)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hid, GetApplicationEventTarget(), 0, &ref)
        if let r = ref { hotkeys.append(r) }
    }
    
    func unregister() {
        for r in hotkeys { UnregisterEventHotKey(r) }
        hotkeys.removeAll()
        if let h = eventHandler { RemoveEventHandler(h); eventHandler = nil }
    }
}

// MARK: - App State
enum AppState {
    case idle, recording, transcribing
    var icon: String {
        switch self {
        case .idle: return "\u{26A1}"       // ⚡
        case .recording: return "\u{1F534}"  // 🔴
        case .transcribing: return "\u{23F3}" // ⏳
        }
    }
    var tooltip: String {
        switch self {
        case .idle: return "QuickFlow — Ready"
        case .recording: return "QuickFlow — Recording..."
        case .transcribing: return "QuickFlow — Transcribing..."
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var state: AppState = .idle
    private let recorder = NativeRecorder()
    private var startMenuItem: NSMenuItem!
    private var stopMenuItem: NSMenuItem!
    private var vttHeaderItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Warm up mic permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        
        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkey = { [weak self] action in
            switch action {
            case .startRecording: self?.startRecording()
            case .stopTranscribe: self?.stopAndTranscribe()
            }
        }
        hotkeyManager.register()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let qa = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        qa.isEnabled = false; menu.addItem(qa)
        menu.addItem(buildMenuItem(title: "Open Terminal", action: #selector(openTerminal), key: "t"))
        menu.addItem(buildMenuItem(title: "Open Finder", action: #selector(openFinder), key: "f"))
        menu.addItem(buildMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), key: "s"))
        menu.addItem(buildMenuItem(title: "Lock Screen", action: #selector(lockScreen), key: "l"))
        menu.addItem(NSMenuItem.separator())
        let sys = NSMenuItem(title: "System", action: nil, keyEquivalent: "")
        sys.isEnabled = false; menu.addItem(sys)
        menu.addItem(buildMenuItem(title: "Empty Clipboard", action: #selector(emptyClipboard), key: "e"))
        menu.addItem(buildMenuItem(title: "Toggle Dark Mode", action: #selector(toggleDarkMode), key: "d"))
        menu.addItem(NSMenuItem.separator())
        
        vttHeaderItem = NSMenuItem(title: "🎙️ Voice to Text", action: nil, keyEquivalent: "")
        vttHeaderItem.isEnabled = false; menu.addItem(vttHeaderItem)
        startMenuItem = buildMenuItem(title: "Start Recording", action: #selector(startRecording), key: "R")
        startMenuItem.keyEquivalentModifierMask = [.option, .command]; menu.addItem(startMenuItem)
        stopMenuItem = buildMenuItem(title: "Stop & Transcribe", action: #selector(stopAndTranscribe), key: "T")
        stopMenuItem.keyEquivalentModifierMask = [.option, .command]; stopMenuItem.isEnabled = false; menu.addItem(stopMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        let util = NSMenuItem(title: "Utilities", action: nil, keyEquivalent: "")
        util.isEnabled = false; menu.addItem(util)
        let wifi = NSMenuItem(title: "Wi-Fi", action: nil, keyEquivalent: "")
        let ws = NSMenu()
        ws.addItem(buildMenuItem(title: "Turn Wi-Fi Off", action: #selector(turnWifiOff), key: ""))
        ws.addItem(buildMenuItem(title: "Turn Wi-Fi On", action: #selector(turnWifiOn), key: ""))
        wifi.submenu = ws; menu.addItem(wifi)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildMenuItem(title: "About QuickFlow", action: #selector(showAbout), key: ""))
        menu.addItem(buildMenuItem(title: "Quit", action: #selector(quitApp), key: "q"))
        statusItem.menu = menu
        updateMenuState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        recorder.stop()
        hotkeyManager.unregister()
    }
    
    // MARK: - State
    private func setState(_ new: AppState) { state = new; updateStatusIcon(); updateMenuState() }
    private func updateStatusIcon() {
        guard let b = statusItem.button else { return }
        b.title = state.icon; b.toolTip = state.tooltip
    }
    private func updateMenuState() {
        switch state {
        case .idle:
            vttHeaderItem.title = "🎙️ Voice to Text"
            startMenuItem.isEnabled = true; stopMenuItem.isEnabled = false
        case .recording:
            vttHeaderItem.title = "🔴 Recording..."
            startMenuItem.isEnabled = false; stopMenuItem.isEnabled = true
        case .transcribing:
            vttHeaderItem.title = "⏳ Transcribing..."
            startMenuItem.isEnabled = false; stopMenuItem.isEnabled = false
        }
    }
    
    // MARK: - Actions
    private func buildMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.target = self; return i
    }
    @objc func openTerminal() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")); runAppleScript("tell application \"Terminal\" to activate") }
    @objc func openFinder() { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSHomeDirectory())]) }
    @objc func takeScreenshot() { let t = Process(); t.launchPath = "/usr/sbin/screencapture"; t.arguments = ["-i", "-c"]; t.launch(); t.waitUntilExit() }
    @objc func lockScreen() { runAppleScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}") }
    @objc func emptyClipboard() { NSPasteboard.general.clearContents(); notify("Clipboard emptied") }
    @objc func toggleDarkMode() { runAppleScript("tell application \"System Events\"\ntell appearance preferences\nset dark mode to not dark mode\nend tell\nend tell") }
    @objc func turnWifiOff() { runShell("/usr/sbin/networksetup", args: ["-setairportpower", "en0", "off"]) }
    @objc func turnWifiOn() { runShell("/usr/sbin/networksetup", args: ["-setairportpower", "en0", "on"]) }
    @objc func showAbout() {
        let a = NSAlert()
        a.messageText = "QuickFlow"; a.informativeText = "Production voice-to-text.\n\nVersion 2.2\nNative recording + Python pipeline\n\n⌥⌘R — Record\n⌥⌘T — Transcribe"
        a.alertStyle = .informational; a.addButton(withTitle: "OK"); a.runModal()
    }
    @objc func quitApp() { NSApplication.shared.terminate(nil) }
    
    // MARK: - Voice to Text (Native Recording)
    @objc func startRecording() {
        guard state == .idle else { return }
        
        // Check mic permission
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status != .authorized {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted { self?.startRecording() }
                        else { self?.notify("Mic access denied — System Settings → Privacy") }
                    }
                }
            } else {
                notify("Mic access denied — System Settings → Privacy → Microphone")
            }
            return
        }
        
        // Record natively (uses app's own mic permission — no subprocess)
        if recorder.start() {
            setState(.recording)
        } else {
            notify("Failed to start recording")
        }
    }
    
    @objc func stopAndTranscribe() {
        guard state == .recording else { return }
        setState(.transcribing)
        
        // Stop native recorder (WAV is written to /tmp/quickflow-orchestrator.wav)
        recorder.stop()
        
        // Hand off to Python orchestrator for transcription only
        // Look for backend inside the app bundle's Resources, fall back to project dir
        guard let bundleResources = Bundle.main.resourcePath else {
            self.notify("Internal error: bundle path missing")
            return
        }
        let backendPath = bundleResources + "/backend/server.py"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.launchPath = "/usr/bin/python3"
            task.arguments = [backendPath, "transcribe-file"]
            task.currentDirectoryPath = bundleResources
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.launch()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            DispatchQueue.main.async {
                self?.setState(.idle)
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if trimmed.contains("\"status\": \"error\"") {
                        self?.notify("Transcription failed")
                    }
                    NSLog("[QuickFlow] \(trimmed)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func runAppleScript(_ script: String) {
        let t = Process(); t.launchPath = "/usr/bin/osascript"; t.arguments = ["-e", script]; t.launch()
    }
    private func runShell(_ cmd: String, args: [String]) {
        let t = Process(); t.launchPath = cmd; t.arguments = args; t.launch()
    }
    private func notify(_ body: String) {
        let c = UNMutableNotificationContent(); c.title = "QuickFlow"; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
