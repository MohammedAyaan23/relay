import Foundation

/// Builds the "Relay" note's HTML body with the newest dated line directly under the title.
public enum NoteBody {
    /// Marks the note as Relay's own, so a note the user happens to title "Relay" is never rewritten.
    public static let marker = "Voice notes from Relay"
    static let title = "<div><h1>Relay</h1></div><div><i>\(marker)</i></div>"

    public static func prepend(entry: String, at date: Date, to body: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm"
        let line = "<div>\(formatter.string(from: date)) — \(escape(entry))</div>"
        guard let body, !body.isEmpty else { return title + line }
        guard let marker = body.range(of: marker),
              let close = body.range(of: "</div>", range: marker.upperBound..<body.endIndex)
        else { return title + line + body }
        return String(body[..<close.upperBound]) + line + String(body[close.upperBound...])
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
