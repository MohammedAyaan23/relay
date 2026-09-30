import AppKit

/// Saves the clipboard, swaps in text to paste, then restores it only if nothing else changed it.
@MainActor
public enum PasteboardSwap {
    public typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]
    /// Tells clipboard managers not to record Relay's temporary dictation (nspasteboard.org convention).
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// How password managers mark secrets on the clipboard (nspasteboard.org convention).
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    public static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    /// Writes `text` and returns the change count to compare against when restoring.
    public static func write(_ text: String, to pasteboard: NSPasteboard) -> Int {
        // This Mac only: dictated text shouldn't reach other devices through Universal Clipboard.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    @discardableResult
    public static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard, ifChangeCount changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        // Never put a password manager's secret back: an app pasting late would paste it instead of the
        // dictated text. Empty the clipboard instead (password managers clear it soon anyway).
        if snapshot.contains(where: { $0[concealedType] != nil }) {
            pasteboard.clearContents()
            return false
        }
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }
}
