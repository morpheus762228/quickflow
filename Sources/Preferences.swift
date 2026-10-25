import Foundation

enum AppInfo {
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}

final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let inputDevice = "inputDeviceUID"
        static let modelPath = "modelPath"
        static let language = "language"
        static let autoPaste = "autoPaste"
        static let restoreClipboard = "restoreClipboard"
        static let playSounds = "playSounds"
        static let smartFormatting = "smartFormatting"
        static let vocabulary = "vocabulary"
        static let hasOnboarded = "hasOnboarded"
        static let liveSubtitles = "liveSubtitles"
    }

    var inputDeviceUID: String {
        get { defaults.string(forKey: Key.inputDevice) ?? "" }
        set { defaults.set(newValue, forKey: Key.inputDevice) }
    }

    var modelPath: String {
        get { defaults.string(forKey: Key.modelPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.modelPath) }
    }

    var language: String {
        get { defaults.string(forKey: Key.language) ?? "en" }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    var autoPaste: Bool {
        get { defaults.object(forKey: Key.autoPaste) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    var restoreClipboard: Bool {
        get { defaults.object(forKey: Key.restoreClipboard) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.restoreClipboard) }
    }

    var playSounds: Bool {
        get { defaults.object(forKey: Key.playSounds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSounds) }
    }

    var smartFormatting: Bool {
        get { defaults.object(forKey: Key.smartFormatting) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.smartFormatting) }
    }

    var vocabulary: String {
        get { defaults.string(forKey: Key.vocabulary) ?? "" }
        set { defaults.set(newValue, forKey: Key.vocabulary) }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// Show the transcript as it grows, in the floating panel, while recording.
    var liveSubtitles: Bool {
        get { defaults.object(forKey: Key.liveSubtitles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.liveSubtitles) }
    }

    var vocabularyPrompt: String? {
        let trimmed = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clipped = String(trimmed.prefix(220))
        return "Vocabulary and names used by the speaker: \(clipped)."
    }
}
