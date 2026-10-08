public enum AppTarget: Equatable, Sendable {
    case frontmost
    case named(String)
    /// Just the verb ("quit", "hide"): no app named and no "this app" / "it", so possibly a misheard word.
    case unspecified
}

/// Which app a quit/hide command means: a spoken name, or the app in front ("this app", nothing).
public enum AppTargetParser {
    static let dropWords: Set<String> = ["quit", "exit", "close", "hide", "completely", "the", "app",
                                         "application", "please", "down", "out", "of", "minimize", "minimise",
                                         "full", "screen", "fullscreen", "window", "tab", "make", "go", "into",
                                         "mode", "enter", "current", "front", "active", "that", "my"]

    static let targetWords: Set<String> = ["app", "application", "window", "tab", "screen", "fullscreen", "current",
                                           "front", "active", "that", "my"]

    public static func parse(_ transcript: String) -> AppTarget {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        let rest = words.filter { !dropWords.contains($0) }
        if rest.isEmpty {
            // "quit the app", "close the tab", "the current app" point at the front app; a bare verb doesn't.
            return words.contains(where: targetWords.contains) ? .frontmost : .unspecified
        }
        if rest == ["this"] || rest == ["this", "window"] || rest == ["it"] { return .frontmost }
        return .named(rest.joined(separator: " "))
    }
}
