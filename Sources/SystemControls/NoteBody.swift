import Foundation

/// Builds the "Relay" note's HTML body with the newest dated line directly under the title.
public enum NoteBody {
    static let title = "<div><h1>Relay</h1></div>"

    public static func prepend(entry: String, at date: Date, to body: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm"
        let line = "<div>\(formatter.string(from: date)) — \(escape(entry))</div>"
        guard let body, !body.isEmpty else { return title + line }
        guard let heading = body.range(of: "</h1>") else { return title + line + body }
        var cut = heading.upperBound
        if body[cut...].hasPrefix("</div>") { cut = body.index(cut, offsetBy: 6) }
        return String(body[..<cut]) + line + String(body[cut...])
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
