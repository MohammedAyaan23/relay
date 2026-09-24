public struct ClaudeResult: Equatable, Sendable {
    public let text: String?
    public let sessionID: String
    public let durationMs: Int
    public let costUSD: Double
    public let isError: Bool
    /// One entry per tool call Claude wasn't allowed to make, e.g. "Bash: python3 -c 'print(1)'".
    public let deniedTools: [String]

    public init(text: String?, sessionID: String, durationMs: Int, costUSD: Double, isError: Bool, deniedTools: [String]) {
        self.text = text
        self.sessionID = sessionID
        self.durationMs = durationMs
        self.costUSD = costUSD
        self.isError = isError
        self.deniedTools = deniedTools
    }
}

public enum ClaudeEvent: Equatable, Sendable {
    case sessionStarted(sessionID: String)
    case text(String)
    case toolUse(name: String, summary: String)
    case toolResult(isError: Bool)
    case finished(ClaudeResult)
    /// The process exited with a non-zero status. `stderrTail` is the last 20 lines of stderr.
    case failed(exitCode: Int32, stderrTail: String)
    /// The job ended because Relay stopped it.
    case stopped
    /// A line Relay doesn't display: hooks, thinking, rate limits, unknown types, invalid JSON.
    case ignored(type: String)
}
