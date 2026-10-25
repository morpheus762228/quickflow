import AppKit
import AVFoundation
import ApplicationServices

enum MicrophonePermission {
    case granted
    case denied
    case undetermined
}

enum SettingsPane {
    case microphone
    case accessibility
}

enum Permissions {
    static var microphone: MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .undetermined
        }
    }

    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    @discardableResult
    static func promptAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func open(_ pane: SettingsPane) {
        switch pane {
        case .microphone:
            openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    private static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
