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
    /// "open sound settings", "launch lock screen settings" are app requests, not device commands.
    static let appLeadIns = ["open", "launch"]
    static let questionWords = ["what", "when", "who", "why", "how"]
    /// Words that make a command about files; an "open…" command with one of these is a file request.
    static let fileWords = ["file", "files", "document", "documents", "doc", "pdf", "spreadsheet", "presentation",
                            "report", "agreement", "contract", "invoice", "folder", "directory"]
    static let fileWordsExceptFolders = fileWords.filter { $0 != "folder" && $0 != "directory" }
    static let windowWords = ["window", "tab", "this", "it"]

    static let rules: [Rule] = [
        Rule(intent: .screenshot, anyOf: ["screenshot", "screen shot", "screen capture", "capture the screen"]),
        Rule(intent: .quitApp, anyOf: ["quit", "exit"], startsWith: ["quit", "exit"],
             noneOf: ["playing", "music", "full screen"]),
        Rule(intent: .quitApp, anyOf: ["close"], alsoAnyOf: ["completely"]),
        Rule(intent: .hideApp, anyOf: ["hide"], startsWith: ["hide"]),
        Rule(intent: .minimizeWindow, anyOf: ["minimize", "minimise"]),
        Rule(intent: .fullScreen, anyOf: ["full screen", "fullscreen"]),
        Rule(intent: .closeWindow, anyOf: ["close"], alsoAnyOf: windowWords, noneOf: ["completely"]),
        Rule(intent: .quitApp, anyOf: ["close"], startsWith: ["close"], noneOf: windowWords),
        Rule(intent: .createFolder, anyOf: ["folder", "directory"], alsoAnyOf: ["create", "make", "new", "add"]),
        Rule(intent: .createFile, anyOf: fileWordsExceptFolders, alsoAnyOf: ["create", "make", "new"]),
        Rule(intent: .revealFile, anyOf: ["finder", "reveal"]),
        Rule(intent: .findFile, anyOf: ["where is", "where did", "where s", "locate"]),
        Rule(intent: .findFile, anyOf: ["find"], alsoAnyOf: fileWords),
        Rule(intent: .openFile, anyOf: ["open"], alsoAnyOf: fileWords, startsWith: ["open"]),
        Rule(intent: .lock, anyOf: ["lock"], noneOf: ["settings", "pick"]),
        Rule(intent: .darkMode, anyOf: ["dark mode", "light mode", "dark theme", "light theme", "appearance"]),
        Rule(intent: .focus, anyOf: ["do not disturb", "focus", "notifications", "silence my mac"],
             noneOf: ["show", "clear", "check", "read", "see"]),
        Rule(intent: .brightness, anyOf: ["brightness", "brighter", "dimmer", "dim", "too bright", "too dark"]),
        Rule(intent: .volume, anyOf: ["volume", "louder", "quieter", "mute", "unmute", "too loud", "too quiet",
                                      "sound", "can t hear", "cannot hear"]),
        Rule(intent: .mediaPrevious, anyOf: ["previous", "last track", "last song", "back a song", "back a track"],
             noneOf: questionWords),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], startsWith: ["next", "skip"],
             noneOf: questionWords + ["week", "month", "year", "time", "day", "weekend"]),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], alsoAnyOf: ["song", "track", "one"], noneOf: questionWords),
        Rule(intent: .mediaPlayPause,
             anyOf: ["play", "pause", "resume", "unpause", "stop the music", "stop playing", "stop the song"],
             noneOf: ["open", "launch"] + documentNouns),
    ]

    public static func match(_ transcript: String) -> RoutedIntent? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        let padded = " \(words) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        func starts(_ phrase: String) -> Bool { padded.hasPrefix(" \(phrase) ") }

        // Claude requests and web searches are Laya's. "open/launch …" is Laya's unless it names a file word.
        let namesFile = fileWords.contains(where: has)
        if has("claude") || webLeadIns.contains(where: starts)
            || (!namesFile && appLeadIns.contains(where: starts)) { return nil }

        return rules.first { rule in
            rule.anyOf.contains(where: has)
                && (rule.alsoAnyOf.isEmpty || rule.alsoAnyOf.contains(where: has))
                && (rule.startsWith.isEmpty || rule.startsWith.contains(where: starts))
                && !rule.noneOf.contains(where: has)
        }?.intent
    }
}
