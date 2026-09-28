import Foundation

/// The text of a spoken note, after "note that", "take a note", and so on.
public enum NoteParser {
    static let leadIns = [
        "take a note that", "make a note that", "add a note saying", "add a note that", "save a note about",
        "take a note", "make a note", "add a note", "save a note", "note that", "note down", "jot down", "jot",
    ] // longest first

    public static func text(from transcript: String) -> String? {
        var rest = Substring(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        for phrase in leadIns {
            if let end = LeadIn.matchEnd(of: phrase, in: rest) {
                rest = rest[end...]
                break
            }
        }
        let text = rest.drop { $0 == " " || $0 == ":" || $0 == "," }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
