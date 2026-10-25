import Foundation

struct ModelInfo {
    let path: String
    let fileName: String
    let displayName: String
    let size: Int64
    let isBundled: Bool
}

enum ModelStore {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("QuickFlow", isDirectory: true)
    }

    static var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("models", isDirectory: true)
    }

    static func prepareDirectories() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    private static let displayNames: [String: String] = [
        "ggml-tiny.en": "Tiny — English",
        "ggml-base.en": "Base — English",
        "ggml-small.en": "Small — English",
        "ggml-medium.en": "Medium — English",
        "ggml-large-v3-turbo": "Large v3 Turbo — Multilingual",
        "ggml-large-v3": "Large v3 — Multilingual"
    ]

    private static let priority: [String: Int] = [
        "ggml-large-v3-turbo": 0,
        "ggml-small.en": 1,
        "ggml-base.en": 2,
        "ggml-medium.en": 3,
        "ggml-tiny.en": 4,
        "ggml-large-v3": 5
    ]

    static func availableModels() -> [ModelInfo] {
        var found: [String: ModelInfo] = [:]

        func scan(_ directory: URL?, bundled: Bool) {
            guard let directory else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension.lowercased() == "bin" {
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("ggml-") else { continue }
                let existing = found[name]
                if existing?.isBundled == true && !bundled { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                let base = displayNames[name] ?? name.replacingOccurrences(of: "ggml-", with: "")
                let megabytes = size > 0 ? " · \(size / 1_000_000) MB" : ""
                found[name] = ModelInfo(
                    path: url.path,
                    fileName: url.lastPathComponent,
                    displayName: base + megabytes,
                    size: size,
                    isBundled: bundled
                )
            }
        }

        scan(Bundle.main.resourceURL?.appendingPathComponent("models", isDirectory: true), bundled: true)
        scan(modelsDirectory, bundled: false)

        return found.values.sorted { lhs, rhs in
            let left = priority[lhs.fileName.replacingOccurrences(of: ".bin", with: "")] ?? 99
            let right = priority[rhs.fileName.replacingOccurrences(of: ".bin", with: "")] ?? 99
            if left != right { return left < right }
            return lhs.displayName < rhs.displayName
        }
    }

    static func activeModelPath(preferred: String) -> String? {
        if !preferred.isEmpty, FileManager.default.fileExists(atPath: preferred) {
            return preferred
        }
        return availableModels().first?.path
    }
}
