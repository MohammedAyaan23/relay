/// Pulls the search terms out of a spoken web-search command.
public enum SearchQueryExtractor {
    static let leadIns = [
        "search the web for", "search the internet for", "search online for", "search for", "search",
        "google", "look up", "find",
    ]

    /// The search terms, or nil if nothing is left after removing the lead-in.
    public static func query(from transcript: String) -> String? {
        let query = LeadIn.strip(transcript, phrases: leadIns)
        return query.isEmpty ? nil : query
    }
}
