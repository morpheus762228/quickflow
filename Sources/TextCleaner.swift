import Foundation

enum DictationStyle: String {
    case prose
    case email
    case chat
    case code
}

enum TextCleaner {
    private static let hesitations = try! NSRegularExpression(
        pattern: #"(?i)\b(?:um+|uh+|uhm+|erm+|hmm+)\b[,\s]*"#
    )

    private static let stutters = try! NSRegularExpression(
        pattern: #"(?i)\b([A-Za-z][A-Za-z'’\-]*)(?:\s+\1\b)+"#
    )

    private static let lowercaseI = try! NSRegularExpression(pattern: #"\bi\b"#)
    private static let lowercaseIContraction = try! NSRegularExpression(
        pattern: #"\bi(['’])(m|ll|ve|d)\b"#,
        options: [.caseInsensitive]
    )
    private static let repeatedSpaces = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)
    private static let spaceBeforePunctuation = try! NSRegularExpression(pattern: #"[ \t]+([,.;:!?])"#)
    private static let doubledPunctuation = try! NSRegularExpression(pattern: #"([,.;:!?])\1+"#)

    static func style(for bundleIdentifier: String?) -> DictationStyle {
        guard let bundleIdentifier else { return .prose }
        let id = bundleIdentifier.lowercased()
        if ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail"].contains(where: { id.hasPrefix($0) }) {
            return .email
        }
        if ["com.tinyspeck.slackmacgap", "com.apple.mobilesms", "com.hnc.discord",
            "com.apple.ichat", "org.whispersystems.signal-desktop", "net.whatsapp.whatsapp",
            "com.microsoft.teams", "com.facebook.archon"].contains(where: { id.hasPrefix($0) }) {
            return .chat
        }
        if ["com.apple.dt.xcode", "com.microsoft.vscode", "com.apple.terminal",
            "com.googlecode.iterm2", "dev.zed.zed", "com.cursor.cursor",
            "com.sublimetext.4", "com.jetbrains"].contains(where: { id.hasPrefix($0) }) {
            return .code
        }
        return .prose
    }

    static func clean(_ raw: String, style: DictationStyle = .prose) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return "" }

        text = replace(hesitations, in: text, with: "")
        text = replace(stutters, in: text, with: "$1")
        text = replace(lowercaseIContraction, in: text, with: "I$1$2")
        text = replace(lowercaseI, in: text, with: "I")
        text = replace(repeatedSpaces, in: text, with: " ")
        text = replace(spaceBeforePunctuation, in: text, with: "$1")
        text = replace(doubledPunctuation, in: text, with: "$1")

        text = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return "" }

        if style != .code {
            text = capitalizeSentences(text)
        }

        if style == .prose || style == .email {
            text = terminateSentence(text)
        }

        return text
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: character.uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" || character == "\n" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    private static func terminateSentence(_ text: String) -> String {
        let closing: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]
        var lastMeaningful: Character?
        for character in text.reversed() {
            if character.isWhitespace { continue }
            if closing.contains(character) { continue }
            lastMeaningful = character
            break
        }
        guard let lastMeaningful else { return text }
        if ".!?…".contains(lastMeaningful) || text.hasSuffix("\n") {
            return text
        }
        return text + "."
    }
}
