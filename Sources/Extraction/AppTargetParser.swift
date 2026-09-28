public enum AppTarget: Equatable, Sendable {
    case frontmost
    case named(String)
}

/// Which app a quit/hide command means: a spoken name, or the app in front ("this app", nothing).
public enum AppTargetParser {
    static let dropWords: Set<String> = ["quit", "exit", "close", "hide", "completely", "the", "app",
                                         "application", "please", "down", "out", "of", "minimize", "minimise",
                                         "full", "screen", "fullscreen", "window", "tab", "make", "go", "into",
                                         "mode", "enter", "current", "front", "active", "that", "my"]

    public static func parse(_ transcript: String) -> AppTarget {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        let rest = words.filter { !dropWords.contains($0) }
        if rest.isEmpty || rest == ["this"] || rest == ["this", "window"] || rest == ["it"] { return .frontmost }
        return .named(rest.joined(separator: " "))
    }
}
