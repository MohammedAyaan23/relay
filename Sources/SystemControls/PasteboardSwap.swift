import AppKit

/// Saves the clipboard, swaps in text to paste, then restores it only if nothing else changed it.
@MainActor
public enum PasteboardSwap {
    public typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    public static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    /// Writes `text` and returns the change count to compare against when restoring.
    public static func write(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    public static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard, ifChangeCount changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }
}
