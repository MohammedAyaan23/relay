import Foundation

public enum FileLocation: String, Equatable, Sendable, CaseIterable {
    case desktop, documents, downloads, home
}

public struct FileRequest: Equatable, Sendable {
    public var name: String?
    public var location: FileLocation?
    public var fileExtension: String?

    public init(name: String?, location: FileLocation?, fileExtension: String?) {
        self.name = name
        self.location = location
        self.fileExtension = fileExtension
    }
}

/// Reads file commands: "make a folder called invoices on the desktop", "open the budget spreadsheet".
public enum FileRequestParser {
    static let fileWords: Set<String> = ["file", "files", "document", "documents", "doc", "pdf", "spreadsheet",
                                         "presentation", "report", "agreement", "contract", "invoice", "folder",
                                         "directory"]
    static let prepositions: Set<String> = ["in", "on", "inside", "into"]
    static let articles: Set<String> = ["the", "my"]
    static let searchDropWords: Set<String> = ["open", "find", "locate", "show", "reveal", "where", "is", "s",
                                               "did", "put", "save", "saved", "my", "the", "a", "an", "that",
                                               "this", "it", "please", "i", "me", "for", "in", "finder", "called",
                                               "named"]

    public static func parse(_ transcript: String) -> FileRequest {
        let words = tokens(transcript)
        let lower = words.map { $0.lowercased() }

        var nameWords: [String] = []
        if let marker = lower.firstIndex(where: { $0 == "called" || $0 == "named" }) {
            var i = marker + 1
            while i < words.count, !startsLocationPhrase(lower, at: i) {
                nameWords.append(words[i])
                i += 1
            }
        }
        var fileExtension: String?
        if let dot = nameWords.firstIndex(where: { $0.lowercased() == "dot" }), dot + 1 < nameWords.count {
            fileExtension = nameWords[dot + 1].lowercased()
            nameWords = Array(nameWords[..<dot])
        }
        let name = nameWords.isEmpty ? nil : nameWords.joined(separator: " ")
        return FileRequest(name: name, location: location(in: lower), fileExtension: fileExtension)
    }

    /// Search text for find/open/reveal: the transcript minus lead-ins, filler and file words.
    public static func query(_ transcript: String) -> String? {
        let lower = tokens(transcript).map { $0.lowercased() }
        var kept: [String] = []
        for (i, word) in lower.enumerated() {
            // "report dot pdf" is a file name even though "report" and "pdf" are file words.
            let isExtension = i > 0 && lower[i - 1] == "dot"
            let isNameBeforeExtension = i + 1 < lower.count && lower[i + 1] == "dot"
            if isExtension || isNameBeforeExtension
                || (!searchDropWords.contains(word) && !fileWords.contains(word)) { kept.append(word) }
        }
        var text = kept.joined(separator: " ")
        if text.isEmpty, let fileWord = lower.first(where: { fileWords.contains($0) && $0 != "file" && $0 != "files" }) {
            text = fileWord
        }
        text = text.replacingOccurrences(of: " dot ", with: ".")
        return text.isEmpty ? nil : text
    }

    /// Words with case kept; "notes.md" becomes "notes dot md" so spoken and typed extensions look alike.
    static func tokens(_ transcript: String) -> [String] {
        let dotted = transcript.replacing(/(\w)\.(\w)/) { "\($0.output.1) dot \($0.output.2)" }
        let spaced = String(dotted.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").map(String.init)
    }

    /// A location word counts after a preposition ("on the desktop") or before "folder" ("the downloads folder").
    static func location(in lower: [String]) -> FileLocation? {
        for (i, word) in lower.enumerated() {
            guard let place = FileLocation(rawValue: word) else { continue }
            let followedByFolder = i + 1 < lower.count && lower[i + 1] == "folder"
            if followedByFolder || precededByPreposition(lower, at: i) { return place }
        }
        return nil
    }

    static func precededByPreposition(_ lower: [String], at index: Int) -> Bool {
        var i = index - 1
        while i >= 0, articles.contains(lower[i]) { i -= 1 }
        return i >= 0 && prepositions.contains(lower[i])
    }

    static func startsLocationPhrase(_ lower: [String], at index: Int) -> Bool {
        guard prepositions.contains(lower[index]) else { return false }
        var i = index + 1
        while i < lower.count, articles.contains(lower[i]) { i += 1 }
        return i < lower.count && FileLocation(rawValue: lower[i]) != nil
    }
}
