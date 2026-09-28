public enum SwitchCommand: Equatable, Sendable {
    case on
    case off
    case toggle
}

/// Reads on/off requests. `darkMode` and `focusOn` handle words that flip the meaning.
public enum SwitchParser {
    static let offWords = ["off", "disable", "stop", "turn off", "deactivate", "end"]
    static let onWords = ["on", "enable", "start", "turn on", "switch to", "activate"]

    public static func parse(_ transcript: String) -> SwitchCommand {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        if offWords.contains(where: { padded.contains(" \($0) ") }) { return .off }
        if onWords.contains(where: { padded.contains(" \($0) ") }) { return .on }
        return .toggle
    }

    /// "light mode" means dark mode off: "switch to light mode" → .off, "turn off light mode" → .on.
    public static func darkMode(_ transcript: String) -> SwitchCommand {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        let mentionsLight = padded.contains(" light mode ") || padded.contains(" light theme ")
        let base = parse(transcript)
        guard mentionsLight else { return base }
        return base == .off ? .on : .off
    }

    /// Whether Do Not Disturb should be on. Relay can't read Focus state, so a bare request means on,
    /// and "notifications" flips the meaning ("turn off notifications" → on).
    public static func focusOn(_ transcript: String) -> Bool {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        let aboutNotifications = padded.contains(" notifications ") || padded.contains(" notification ")
        switch parse(transcript) {
        case .toggle: return true
        case .on: return !aboutNotifications
        case .off: return aboutNotifications
        }
    }
}
