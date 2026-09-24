public enum RoutedIntent: String, CaseIterable, Sendable, Codable {
    case openApp = "open_app"
    case webSearch = "web_search"
    case askClaude = "ask_claude"
    case newClaudeSession = "new_claude_session"

    /// Wording for messages like "Maybe open an app or search the web?".
    public var displayName: String {
        switch self {
        case .openApp: "open an app"
        case .webSearch: "search the web"
        case .askClaude: "ask Claude"
        case .newClaudeSession: "start a new Claude session"
        }
    }
}

public struct RoutingThresholds: Sendable, Equatable {
    public var gate: Float
    public var choice: Float

    /// `choice` defaults to 0.35: with three options chance is 0.33, and real commands in the phrase set
    /// win with as little as 0.37 (see `make test-routing`).
    public init(gate: Float = 0.5, choice: Float = 0.35) {
        self.gate = gate
        self.choice = choice
    }
}

public struct RoutingDecision: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case intent(RoutedIntent)
        case notACommand
        case ambiguous([RoutedIntent])

        public var logName: String {
            switch self {
            case .intent(let intent): intent.rawValue
            case .notACommand: "not_a_command"
            case .ambiguous: "ambiguous"
            }
        }
    }

    public let outcome: Outcome
    public let gateProbability: Float
    /// Empty when the gate rejected the transcript.
    public let choiceProbabilities: [RoutedIntent: Float]
    public let stateWasTruncated: Bool

    public init(outcome: Outcome, gateProbability: Float, choiceProbabilities: [RoutedIntent: Float], stateWasTruncated: Bool) {
        self.outcome = outcome
        self.gateProbability = gateProbability
        self.choiceProbabilities = choiceProbabilities
        self.stateWasTruncated = stateWasTruncated
    }
}

public enum RoutingError: Error {
    case notPrepared
}

public protocol IntentRouting: Sendable {
    /// Loads the model, reporting human-readable progress. Safe to call more than once.
    func prepare(progress: @escaping @Sendable (String) -> Void) async throws
    func route(_ transcript: String) async throws -> RoutingDecision
    func setThresholds(_ thresholds: RoutingThresholds) async
}
