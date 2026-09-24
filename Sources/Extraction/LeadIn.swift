import Foundation

/// Removes a spoken lead-in ("search for", "tell claude to", …) from the start of a command,
/// keeping the rest of the original text verbatim.
public enum LeadIn {
    /// Only sentence punctuation is trimmed, so "C#", "50%" and "(briefly)" keep their symbols.
    static let sentencePunctuation = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?"))

    static let courtesy = ["can you", "could you", "would you", "will you", "please", "hey relay", "relay", "ok", "okay"]

    /// Removes any courtesy words, then the longest phrase in `phrases`, matching whole words
    /// case-insensitively. Phrases are lowercase words separated by single spaces.
    public static func strip(_ text: String, phrases: [String]) -> String {
        var rest = Substring(text)
        func dropLongest(of candidates: [String]) -> Bool {
            for phrase in candidates.sorted(by: { $0.count > $1.count }) {
                if let end = matchEnd(of: phrase, in: rest) {
                    rest = rest[end...]
                    return true
                }
            }
            return false
        }
        while dropLongest(of: courtesy) {}
        _ = dropLongest(of: phrases)
        return rest.trimmingCharacters(in: sentencePunctuation)
    }

    /// The index just past `phrase` if `text` starts with it as whole words. Any run of
    /// non-alphanumeric characters counts as a word separator.
    static func matchEnd(of phrase: String, in text: Substring) -> Substring.Index? {
        var i = text.startIndex
        for word in phrase.split(separator: " ") {
            while i < text.endIndex, !text[i].isLetter, !text[i].isNumber { i = text.index(after: i) }
            guard text[i...].lowercased().hasPrefix(word) else { return nil }
            i = text.index(i, offsetBy: word.count)
            if i < text.endIndex, text[i].isLetter || text[i].isNumber { return nil }
        }
        return i
    }
}
