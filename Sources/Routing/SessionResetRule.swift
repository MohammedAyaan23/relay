/// Recognises "new Claude session" style requests without the model. As a fourth Laya option, a
/// session-reset choice pulled in unrelated commands (11/14 at best), so it's a fixed phrase instead.
public enum SessionResetRule {
    static let resetWords: Set<String> = ["new", "fresh", "reset", "restart", "clear"]
    static let sessionWords: Set<String> = ["session", "conversation", "chat"]
    /// Real reset requests are short; longer sentences are tasks that happen to mention sessions.
    static let maximumWords = 8

    public static func matches(_ transcript: String) -> Bool {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count <= maximumWords, words.contains("claude") else { return false }
        let asksReset = words.contains { resetWords.contains($0) }
        let namesSession = words.contains { sessionWords.contains($0) }
        let resetsClaudeItself = words.contains("reset") || words.contains("restart")
        return asksReset && (namesSession || resetsClaudeItself)
    }
}
