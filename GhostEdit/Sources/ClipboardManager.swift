import AppKit
import Carbon.HIToolbox

final class ClipboardManager {
    enum ShortcutPosting {
        case annotatedSession
        case hidSystem

        var displayName: String {
            switch self {
            case .annotatedSession:
                return "annotated"
            case .hidSystem:
                return "hid"
            }
        }

        var eventSourceState: CGEventSourceStateID {
            switch self {
            case .annotatedSession:
                return .combinedSessionState
            case .hidSystem:
                return .hidSystemState
            }
        }

        var eventTap: CGEventTapLocation {
            switch self {
            case .annotatedSession:
                return .cgAnnotatedSessionEventTap
            case .hidSystem:
                return .cghidEventTap
            }
        }
    }

    struct Snapshot {
        struct ItemPayload {
            let entries: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [ItemPayload]
        let fallbackString: String?
    }

    private let pasteboard = NSPasteboard.general

    func snapshot() -> Snapshot {
        let capturedItems: [Snapshot.ItemPayload] = (pasteboard.pasteboardItems ?? []).map { item in
            let entries = item.types.compactMap { type -> (type: NSPasteboard.PasteboardType, data: Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type: type, data: data)
            }
            return Snapshot.ItemPayload(entries: entries)
        }

        return Snapshot(items: capturedItems, fallbackString: readPlainText())
    }

    func restore(_ snapshot: Snapshot) {
        pasteboard.clearContents()

        let rebuiltItems: [NSPasteboardItem] = snapshot.items.compactMap { payload in
            let item = NSPasteboardItem()
            var hasEntry = false

            for entry in payload.entries where item.setData(entry.data, forType: entry.type) {
                hasEntry = true
            }

            return hasEntry ? item : nil
        }

        if !rebuiltItems.isEmpty {
            _ = pasteboard.writeObjects(rebuiltItems)
            return
        }

        if let fallbackString = snapshot.fallbackString {
            pasteboard.setString(fallbackString, forType: .string)
        }
    }

    func readPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    func readBestText() -> String? {
        if let plain = readPlainText() {
            return plain
        }

        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attributed.string
        }

        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributed = try? NSAttributedString(
               data: rtfdData,
               options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil
           ) {
            return attributed.string
        }

        return nil
    }

    func readHTMLString() -> String? {
        guard let data = pasteboard.data(forType: .html) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func writePlainText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    func simulateCopyShortcut(using posting: ShortcutPosting) -> Bool {
        simulateShortcut(
            keyCode: CGKeyCode(kVK_ANSI_C),
            modifiers: [.maskCommand],
            posting: posting
        )
    }

    @discardableResult
    func simulatePasteShortcut(using posting: ShortcutPosting) -> Bool {
        simulateShortcut(
            keyCode: CGKeyCode(kVK_ANSI_V),
            modifiers: [.maskCommand],
            posting: posting
        )
    }

    @discardableResult
    private func simulateShortcut(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        posting: ShortcutPosting
    ) -> Bool {
        guard
            let source = CGEventSource(stateID: posting.eventSourceState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        keyDown.post(tap: posting.eventTap)
        keyUp.post(tap: posting.eventTap)
        return true
    }
}
