/// Recognises "new Claude session" style requests without the model. As a fourth Laya option, a
/// session-reset choice pulled in unrelated commands (11/14 at best), so it's a fixed phrase instead.
public enum SessionResetRule {
    static let resetWords: Set<String> = ["new", "fresh", "reset", "restart", "clear"]
    static let sessionWords: Set<String> = ["session", "conversation", "chat"]
    /// Real reset requests are short; longer sentences are tasks that happen to mention sessions.
    static let maximumWords = 8
    /// Every word must come from this list, so "Claude, add a new chat screen" stays a task.
    static let allowedWords: Set<String> = resetWords.union(sessionWords).union([
        "claude", "code", "start", "begin", "over", "a", "an", "the", "and", "with", "please", "my", "our",
        "tell", "ask", "hey", "ok", "okay", "relay", "can", "could", "you", "i", "want", "let", "lets", "s",
        "us", "up", "to", "me", "give", "open",
    ])

    public static func matches(_ transcript: String) -> Bool {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count <= maximumWords, words.contains("claude"),
              words.allSatisfy(allowedWords.contains) else { return false }
        let asksReset = words.contains { resetWords.contains($0) }
        let namesSession = words.contains { sessionWords.contains($0) }
        let resetsClaudeItself = words.contains("reset") || words.contains("restart")
        return asksReset && (namesSession || resetsClaudeItself)
    }
}
