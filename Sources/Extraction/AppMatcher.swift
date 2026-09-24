public enum AppMatch: Equatable, Sendable {
    case found(InstalledApp)
    case notFound(query: String, suggestions: [String])
}

/// Finds the installed app a spoken "open …" command refers to.
public struct AppMatcher: Sendable {
    static let leadIns = ["open up", "open", "launch", "fire up", "start up", "start", "switch to", "bring up", "show me", "show"]

    private let entries: [(app: InstalledApp, key: String)]

    public init(apps: [InstalledApp]) {
        entries = apps.map { ($0, TextNormalizer.normalize($0.name)) }.filter { !$0.key.isEmpty }
    }

    public func match(_ transcript: String) -> AppMatch {
        let text = TextNormalizer.normalize(transcript)

        // 1. An installed app's name appears in the sentence: take the longest such name.
        let padded = " \(text) "
        if let best = entries.filter({ padded.contains(" \($0.key) ") }).max(by: { $0.key.count < $1.key.count }) {
            return .found(best.app)
        }

        // 2. Otherwise fuzzy-match what's left after the lead-in, ignoring spaces ("x code" ≈ "xcode").
        var query = LeadIn.strip(text, phrases: Self.leadIns)
        if query.hasPrefix("the ") { query.removeFirst(4) }
        if query.hasSuffix(" app") { query.removeLast(4) }
        guard !query.isEmpty else { return .notFound(query: "", suggestions: []) }

        let squashed = query.replacingOccurrences(of: " ", with: "")
        let ranked = entries
            .map { entry -> (app: InstalledApp, key: String, distance: Int) in
                let key = entry.key.replacingOccurrences(of: " ", with: "")
                return (entry.app, key, Levenshtein.distance(squashed, key))
            }
            .sorted { $0.distance < $1.distance }

        if let best = ranked.first, best.distance <= max(1, best.key.count / 4) {
            return .found(best.app)
        }
        var suggestions: [String] = []
        for candidate in ranked where !suggestions.contains(candidate.app.name) {
            suggestions.append(candidate.app.name)
            if suggestions.count == 3 { break }
        }
        return .notFound(query: query, suggestions: suggestions)
    }
}
