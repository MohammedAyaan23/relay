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
    /// "close" only counts as a window command right before what's being closed ("close the tab").
    static let closeTargets = ["close the", "close this", "close that", "close my", "close it", "close window",
                               "close tab", "close all"]
    /// Polite openers are dropped so start-of-command rules still apply ("can you close the tab").
    static let courtesy = ["can you", "could you", "would you", "will you", "please", "hey relay", "relay", "ok", "okay"]

    static let rules: [Rule] = [
        // Typing and capture come first: dictated or noted text may contain any command words.
        Rule(intent: .typeText, anyOf: ["type", "dictate", "write"], startsWith: ["type", "dictate", "write"]),
        Rule(intent: .addNote, anyOf: ["take a note", "make a note", "note that", "note down", "jot", "add a note",
                                       "save a note"]),
        Rule(intent: .addReminder, anyOf: ["remind me", "reminder", "don t let me forget"]),
        Rule(intent: .cancelTimer, anyOf: ["timer", "timers"], alsoAnyOf: ["cancel", "stop", "delete", "clear", "remove"]),
        Rule(intent: .timerStatus, anyOf: ["timer", "timers"],
             alsoAnyOf: ["how long", "how much time", "left", "remaining", "status"]),
        Rule(intent: .startTimer, anyOf: ["timer", "countdown", "pomodoro"]),
        Rule(intent: .screenshot, anyOf: ["screenshot", "screen shot", "screen capture", "capture the screen"]),
        Rule(intent: .quitApp, anyOf: ["quit", "exit"], startsWith: ["quit", "exit"],
             noneOf: ["playing", "music", "full screen"]),
        Rule(intent: .quitApp, anyOf: ["close"], alsoAnyOf: ["completely"]),
        Rule(intent: .hideApp, anyOf: ["hide"], startsWith: ["hide"]),
        Rule(intent: .minimizeWindow, anyOf: ["minimize", "minimise"], noneOf: questionWords),
        Rule(intent: .fullScreen, anyOf: ["full screen", "fullscreen"], noneOf: questionWords),
        Rule(intent: .closeWindow, anyOf: closeTargets, alsoAnyOf: windowWords, noneOf: ["completely"] + questionWords),
        Rule(intent: .quitApp, anyOf: ["close"], startsWith: ["close"], noneOf: windowWords),
        Rule(intent: .createFolder, anyOf: ["folder", "directory"], startsWith: ["create", "make", "new", "add"]),
        Rule(intent: .createFile, anyOf: fileWordsExceptFolders, alsoAnyOf: ["called", "named", "new", "empty", "blank"],
             startsWith: ["create", "make", "new"]),
        Rule(intent: .revealFile, anyOf: ["finder", "reveal"]),
        Rule(intent: .findFile, anyOf: ["where is", "where s", "locate"], alsoAnyOf: fileWords),
        Rule(intent: .findFile, anyOf: ["where did"], alsoAnyOf: ["put", "save", "saved", "leave", "keep"]),
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
        var words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var droppedCourtesy = true
        while droppedCourtesy {
            droppedCourtesy = false
            for phrase in courtesy {
                let parts = phrase.split(separator: " ").map(String.init)
                if words.starts(with: parts) {
                    words.removeFirst(parts.count)
                    droppedCourtesy = true
                }
            }
        }
        var padded = " \(words.joined(separator: " ")) "
        // A spoken or typed file name ("notes dot md", "notes.md") counts as naming a file.
        if transcript.lowercased().contains(/[a-z0-9]\.[a-z0-9]/) || padded.contains(" dot ") { padded += "file " }
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
