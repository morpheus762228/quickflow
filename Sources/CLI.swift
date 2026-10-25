import AppKit
import Foundation

@main
struct QuickFlowCLI {
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return
        }

        if arguments.contains("--devices") {
            printDevices()
            return
        }

        if let index = arguments.firstIndex(of: "--check") {
            _ = index
            printDiagnostics()
            return
        }

        if let index = arguments.firstIndex(of: "--render-welcome"), index + 1 < arguments.count {
            renderWelcome(to: arguments[index + 1])
            return
        }

        if let index = arguments.firstIndex(of: "--live-preview"), index + 1 < arguments.count {
            livePreview(path: arguments[index + 1])
            return
        }

        if let index = arguments.firstIndex(of: "--render-live"), index + 1 < arguments.count {
            renderLive(to: arguments[index + 1])
            return
        }

        if let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            let clean = arguments.contains("--clean")
            let style = requestedStyle(from: arguments)
            transcribeFile(path: path, clean: clean, style: style)
            return
        }

        if arguments.contains("--dictate") {
            dictate()
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }

    private static func printUsage() {
        print("""
        QuickFlow — private, on-device dictation for macOS

        USAGE
          QuickFlow.app                 Run the menu bar app
          QuickFlow --dictate           Start recording, stop on Return, print transcript
          QuickFlow --transcribe FILE   Transcribe an audio file
          QuickFlow --transcribe FILE --clean [--style prose|email|chat|code]
          QuickFlow --devices           List audio input devices
          QuickFlow --check             Show permissions, models, and devices
        """)
    }

    private static func printDevices() {
        let devices = AudioDevices.allInputs()
        guard !devices.isEmpty else {
            print("No audio input devices found.")
            return
        }
        for device in devices {
            var tags: [String] = []
            if device.isDefault { tags.append("default") }
            if device.isVirtual { tags.append("virtual") }
            let suffix = tags.isEmpty ? "" : "  [\(tags.joined(separator: ", "))]"
            print("\(device.name)\(suffix)  id=\(device.id)  channels=\(device.channels)")
        }
    }

    private static func printDiagnostics() {
        print("QuickFlow \(AppInfo.version)")
        print("")

        switch Permissions.microphone {
        case .granted: print("Microphone:   granted")
        case .denied: print("Microphone:   denied")
        case .undetermined: print("Microphone:   not requested")
        }
        print("Accessibility: \(Permissions.accessibility ? "granted" : "not granted (auto-paste disabled)")")
        print("")

        let models = ModelStore.availableModels()
        if models.isEmpty {
            print("Models: none installed")
            print("Add a ggml-*.bin file to \(ModelStore.modelsDirectory.path)")
        } else {
            print("Models:")
            for model in models {
                let source = model.isBundled ? "bundled" : model.path
                print("  • \(model.displayName)  (\(source))")
            }
        }
        print("")

        if let device = AudioDevices.defaultInput() {
            print("Default input: \(device.name)\(device.isVirtual ? "  [virtual]" : "")")
        }
        print("QuickFlow will use: \(AudioDevices.preferredInput()?.name ?? "none")")
    }

    /// Developer aid: renders the welcome window's content view to a PNG so the
    /// layout can be checked without screen-recording permission.
    private static func renderWelcome(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = WelcomeWindowController()
        guard let window = controller.window, let view = window.contentView else {
            fail("Could not build welcome window")
        }
        window.setFrame(NSRect(x: 0, y: 0, width: 520, height: 470), display: false)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fail("Could not create bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("Could not encode PNG")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        } catch {
            fail("Write failed: \(error.localizedDescription)")
        }
    }

    /// Developer aid: drives the live subtitle pipeline from a file instead of the mic,
    /// printing every preview update so the rolling-window stitching can be checked.
    private static func livePreview(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            fail("No file at \(path)")
        }
        guard let modelPath = ModelStore.activeModelPath(preferred: Preferences.shared.modelPath) else {
            fail("No model installed. Add a ggml-*.bin file to \(ModelStore.modelsDirectory.path)")
        }

        do {
            let floats = try AudioFileDecoder.floats(at: URL(fileURLWithPath: path))
            let pcm = floats.map { Int16(max(-1, min(1, $0)) * 32767) }
            let engine = try WhisperEngine(modelPath: modelPath)
            let live = LiveTranscriber(engine: engine, language: Preferences.shared.language)
            let started = CFAbsoluteTimeGetCurrent()
            live.onUpdate = { text in
                print(String(format: "[%5.1fs] %@", CFAbsoluteTimeGetCurrent() - started, text))
                fflush(stdout)
            }
            live.start()

            let chunk = Int(0.4 * AudioFileDecoder.sampleRate)
            var offset = 0
            while offset < pcm.count {
                let end = min(offset + chunk, pcm.count)
                live.append(Array(pcm[offset..<end]))
                offset = end
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(2.0))
            live.stop()

            print("--- final ---")
            print(try engine.transcribe(samples: floats, language: Preferences.shared.language, prompt: nil).text)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Developer aid: renders the floating panel with a live subtitle attached.
    private static func renderLive(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let hud = HUDController()
        hud.showListening()
        hud.setTranscript("""
        So the plan for Thursday is to ship the installer, then walk the whole onboarding \
        flow with fresh accounts and note anything that feels slow or confusing before we \
        hand it to the team for a first pass.
        """)
        guard hud.renderSnapshot(to: path) else {
            fail("Could not render the HUD")
        }
        print("wrote \(path)")
    }

    private static func requestedStyle(from arguments: [String]) -> DictationStyle {
        guard let index = arguments.firstIndex(of: "--style"), index + 1 < arguments.count else {
            return .prose
        }
        switch arguments[index + 1].lowercased() {
        case "email": return .email
        case "chat": return .chat
        case "code": return .code
        default: return .prose
        }
    }

    private static func transcribeFile(path: String, clean: Bool, style: DictationStyle) {
        guard FileManager.default.fileExists(atPath: path) else {
            fail("No file at \(path)")
        }
        guard let modelPath = ModelStore.activeModelPath(preferred: Preferences.shared.modelPath) else {
            fail("No model installed. Add a ggml-*.bin file to \(ModelStore.modelsDirectory.path)")
        }

        do {
            let loadStarted = CFAbsoluteTimeGetCurrent()
            let engine = try WhisperEngine(modelPath: modelPath)
            engine.warmUp()
            let readyTime = CFAbsoluteTimeGetCurrent() - loadStarted
            let url = URL(fileURLWithPath: path)
            let transcript = try engine.transcribe(url: url, language: Preferences.shared.language, prompt: nil)
            var text = transcript.text
            if clean {
                text = SmartFormatter.format(text, style: style)
            }
            let speed = transcript.audioDuration / max(transcript.inferenceTime, 0.001)
            let timing = String(
                format: "Ready in %.2fs · %.1fs audio in %.2fs (%.1f× realtime)\n",
                readyTime, transcript.audioDuration, transcript.inferenceTime, speed
            )
            FileHandle.standardError.write(Data(timing.utf8))
            print(text)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func dictate() {
        guard Permissions.microphone == .granted else {
            fail("Microphone permission is not granted. Run QuickFlow.app once and accept the prompt.")
        }
        guard let modelPath = ModelStore.activeModelPath(preferred: Preferences.shared.modelPath) else {
            fail("No model installed. Add a ggml-*.bin file to \(ModelStore.modelsDirectory.path)")
        }

        let engine: WhisperEngine
        do {
            engine = try WhisperEngine(modelPath: modelPath)
        } catch {
            fail(error.localizedDescription)
        }

        let recorder = AudioRecorder()
        var finished = false

        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var failure: Error?

        recorder.onLimitReached = {
            print("Maximum length reached — transcribing.")
            fflush(stdout)
        }

        do {
            try recorder.start(deviceUID: Preferences.shared.inputDeviceUID)
        } catch {
            fail(error.localizedDescription)
        }

        FileHandle.standardError.write(Data("Recording… press Return to stop.\n".utf8))

        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = ""
            while true {
                guard let line = readLine(strippingNewline: false) else { break }
                buffer += line
                if line.contains("\n") { break }
            }
            _ = buffer
            finished = true
            semaphore.signal()
        }

        while !finished && recorder.isRecording {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        _ = semaphore.wait(timeout: .now() + 0.5)

        guard let recording = recorder.stop() else {
            fail("No audio was captured.")
        }
        defer { try? FileManager.default.removeItem(at: recording.url) }

        guard !recording.isSilent else {
            fail("The recording was silent. Check your microphone input.")
        }

        FileHandle.standardError.write(Data("Transcribing…\n".utf8))

        do {
            var text = try engine.transcribe(url: recording.url, language: Preferences.shared.language, prompt: nil).text
            if Preferences.shared.smartFormatting {
                text = SmartFormatter.format(text, style: .prose)
            }
            resultText = text
        } catch {
            failure = error
        }

        if let failure {
            fail(failure.localizedDescription)
        }
        print(resultText ?? "")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("QuickFlow: \(message)\n".utf8))
        exit(1)
    }
}
