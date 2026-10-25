import AppKit
import Carbon.HIToolbox

enum TextInjector {
    struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    static func snapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        } ?? []
        return ClipboardSnapshot(items: items)
    }

    static func restore(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let restored = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }

    @discardableResult
    static func copy(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Returns true when the text was inserted into the target app.
    @discardableResult
    static func paste(_ text: String, restoreClipboard: Bool) -> Bool {
        let previous = restoreClipboard ? snapshot() : nil
        let changeCount = copy(text)

        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            return false
        }

        usleep(45_000)
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: isDown) else {
                return false
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
            usleep(12_000)
        }

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                if NSPasteboard.general.changeCount == changeCount {
                    restore(previous)
                }
            }
        }
        return true
    }
}
