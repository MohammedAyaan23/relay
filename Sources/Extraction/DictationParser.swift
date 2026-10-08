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
        let text = oneLine(String(rest)).drop { $0 == " " || $0 == ":" || $0 == "," }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Pasted text stays on one line: in a terminal a line break would run what came before it, and control
    /// characters (escape sequences, bells) could act as keys. Line breaks and tabs become single spaces.
    static func oneLine(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || scalar == "\t" {
                if !result.hasSuffix(" ") { result.append(" ") }
            } else if scalar.properties.generalCategory != .control { // keeps emoji joiners (format, not control)
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
