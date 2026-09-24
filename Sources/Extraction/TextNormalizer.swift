import Foundation

/// Canonical form for matching spoken text: lowercase, punctuation turned into spaces, single spaces.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        let mapped = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}
