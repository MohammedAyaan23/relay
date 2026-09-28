import Foundation

/// Filters and ranks `mdfind` results: exact name, then prefix, then contains; ties by most recently used.
public enum FileSearch {
    public static let limit = 8
    /// Only this many `mdfind` paths are considered, so a vague query can't stall Relay.
    public static let pathLimit = 300

    public static func rank(paths: [String], query: String, home: URL, lastUsed: (URL) -> Date?) -> [FileMatch] {
        let q = query.lowercased()
        let library = home.appendingPathComponent("Library").path + "/"
        let scored = paths.prefix(pathLimit).compactMap { path -> (match: FileMatch, tier: Int)? in
            guard !path.hasPrefix(library),
                  !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                  !path.contains(".app/")
            else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            let tier = stem == q || name.lowercased() == q ? 0
                : stem.hasPrefix(q) ? 1
                : name.lowercased().contains(q) ? 2
                : 3
            return (FileMatch(name: name, url: url, lastUsed: lastUsed(url)), tier)
        }
        let sorted = scored.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            return (a.match.lastUsed ?? .distantPast) > (b.match.lastUsed ?? .distantPast)
        }
        return sorted.prefix(limit).map(\.match)
    }
}
