import Foundation

/// Turns raw whisper output into text that looks like a person typed it.
enum SmartFormatter {
    static func format(_ text: String, style: DictationStyle) -> String {
        switch style {
        case .prose:
            return finish(prose(text))
        case .email:
            return finish(email(text))
        case .chat:
            return finish(chat(text))
        case .code:
            return finish(code(text))
        }
    }

    // MARK: - Styles

    private static func prose(_ text: String) -> String {
        var body = TextCleaner.clean(text, style: .prose)
        body = spokenPunctuation(body)
        return body
    }

    private static func email(_ text: String) -> String {
        var body = TextCleaner.clean(text, style: .email)
        body = spokenPunctuation(body)

        body = replace(
            #"^(hi|hello|hey|dear)([^.,!?\n]{0,40})[,.]\s+"#,
            in: body,
            with: "$1$2,\n\n",
            options: [.caseInsensitive]
        )
        body = replace(
            #"\s+(thanks|thank you|best|regards|cheers|sincerely)[,.]?$"#,
            in: body,
            with: "\n\n$1",
            options: [.caseInsensitive]
        )
        return body
    }

    private static func chat(_ text: String) -> String {
        var body = TextCleaner.clean(text, style: .chat)
        body = spokenPunctuation(body)
        body = body.replacingOccurrences(of: "\n", with: " ")
        while body.hasSuffix(".") && !body.hasSuffix("..") {
            body.removeLast()
        }
        return body
    }

    private static func code(_ text: String) -> String {
        var body = TextCleaner.clean(text, style: .code)
        body = replaceWord("new line", in: body, with: "\n")
        body = replaceWord("next line", in: body, with: "\n")
        body = replaceWord("new paragraph", in: body, with: "\n\n")

        let symbols: [(String, String)] = [
            ("open brace", "{"),
            ("left brace", "{"),
            ("close brace", "}"),
            ("right brace", "}"),
            ("open bracket", "["),
            ("close bracket", "]"),
            ("open paren", "("),
            ("open parenthesis", "("),
            ("close paren", ")"),
            ("close parenthesis", ")"),
            ("semicolon", ";"),
            ("colon", ":"),
            ("double equals", "=="),
            ("equals", "="),
            ("arrow", "->"),
            ("underscore", "_"),
            ("dot", "."),
            ("comma", ","),
            ("backslash", "\\"),
            ("slash", "/"),
            ("at sign", "@"),
            ("hash", "#"),
            ("dollar sign", "$"),
            ("percent", "%"),
            ("ampersand", "&"),
            ("pipe", "|"),
            ("asterisk", "*"),
            ("plus", "+"),
            ("minus", "-"),
            ("quote", "\""),
            ("single quote", "'"),
            ("backtick", "`")
        ]

        for (word, symbol) in symbols {
            body = replaceWord(word, in: body, with: symbol)
        }
        return body
    }

    // MARK: - Helpers

    private static func finish(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { line in line.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) }
            .joined(separator: "\n")
            .replacingOccurrences(of: " +([,.;:!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func spokenPunctuation(_ text: String) -> String {
        var body = text

        let map: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("question mark", "?"),
            ("exclamation mark", "!"),
            ("exclamation point", "!"),
            ("full stop", "."),
            ("comma", ","),
            ("semicolon", ";"),
            ("colon", ":"),
            ("open quote", "\""),
            ("close quote", "\"")
        ]
        for (word, symbol) in map {
            body = replaceWord(word, in: body, with: symbol)
        }

        body = body.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: " +([,.;:!?])", with: "$1", options: .regularExpression)
        body = body.replacingOccurrences(of: "([,;:])(?=[^\\s\\n])", with: "$1 ", options: .regularExpression)

        if body.lowercased().hasSuffix(" period") {
            body = String(body.dropLast(" period".count)) + "."
        }
        return body
    }

    private static func replaceWord(_ word: String, in text: String, with replacement: String) -> String {
        replaceLiteral(
            "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b",
            in: text,
            with: replacement,
            options: [.caseInsensitive]
        )
    }

    /// Literal replacement: `$` and `\` in the replacement are kept as-is.
    private static func replaceLiteral(
        _ pattern: String,
        in text: String,
        with literal: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let match else { return }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += literal
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    private static func replace(
        _ pattern: String,
        in text: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
