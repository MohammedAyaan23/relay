/// Ordered keyword rules for device commands, checked after `SessionResetRule` and before Laya.
/// Evidence (spec §2): rules + Laya routed 39/40 held-out phrases; Laya alone managed ~50% on many-way choices.
public enum CommandRules {
    struct Rule {
        let intent: RoutedIntent
        /// At least one must appear as whole words.
        let anyOf: [String]
        /// If non-empty, at least one must also appear.
        var alsoAnyOf: [String] = []
        /// If non-empty, the transcript must start with one of these.
        var startsWith: [String] = []
        /// None of these may appear.
        var noneOf: [String] = []
    }

    static let documentNouns = ["file", "files", "document", "pdf", "spreadsheet", "presentation", "report",
                                "agreement", "contract", "invoice"]
    static let webLeadIns = ["search", "google", "look up", "find out"]

    static let rules: [Rule] = [
        Rule(intent: .screenshot, anyOf: ["screenshot", "screen shot", "screen capture", "capture the screen"]),
        Rule(intent: .lock, anyOf: ["lock"]),
        Rule(intent: .darkMode, anyOf: ["dark mode", "light mode", "dark theme", "light theme", "appearance"]),
        Rule(intent: .focus, anyOf: ["do not disturb", "focus", "notifications", "silence my mac"]),
        Rule(intent: .brightness, anyOf: ["brightness", "brighter", "dimmer", "dim", "too bright", "too dark"]),
        Rule(intent: .volume, anyOf: ["volume", "louder", "quieter", "mute", "unmute", "too loud", "sound"]),
        Rule(intent: .mediaPrevious, anyOf: ["previous", "last track", "last song", "back a song", "back a track"]),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], startsWith: ["next", "skip"]),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], alsoAnyOf: ["song", "track", "one"]),
        Rule(intent: .mediaPlayPause,
             anyOf: ["play", "pause", "resume", "unpause", "stop the music", "stop playing", "stop the song"],
             noneOf: ["open", "launch"] + documentNouns),
    ]

    public static func match(_ transcript: String) -> RoutedIntent? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        let padded = " \(words) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        func starts(_ phrase: String) -> Bool { padded.hasPrefix(" \(phrase) ") }

        // Claude requests and web searches are Laya's, even when they mention device words.
        if has("claude") || webLeadIns.contains(where: starts) { return nil }

        return rules.first { rule in
            rule.anyOf.contains(where: has)
                && (rule.alsoAnyOf.isEmpty || rule.alsoAnyOf.contains(where: has))
                && (rule.startsWith.isEmpty || rule.startsWith.contains(where: starts))
                && !rule.noneOf.contains(where: has)
        }?.intent
    }
}
