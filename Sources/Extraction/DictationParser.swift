import Foundation

/// The words to type: everything after "type" / "dictate" / "write", kept exactly as spoken.
public enum DictationParser {
    static let leadIns = ["type out", "write down", "type", "dictate", "write"] // longest first

    public static func text(from transcript: String) -> String? {
        var rest = Substring(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        var droppedCourtesy = true
        while droppedCourtesy {
            droppedCourtesy = false
            for phrase in LeadIn.courtesy {
                if let end = LeadIn.matchEnd(of: phrase, in: rest) {
                    rest = rest[end...]
                    droppedCourtesy = true
                }
            }
        }
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
