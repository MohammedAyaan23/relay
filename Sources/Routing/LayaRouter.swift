import FluidUse

/// Routes transcripts with Laya: a yes/no "is this a command?" gate, then a choice between intents.
/// There is deliberately no "none" option: in the spike it swallowed real commands (6/11 correct).
public actor LayaRouter: IntentRouting {
    static let gateQuestion = LayaQuestion.noul(
        "Is the user giving the computer an instruction to perform an action?",
        falseDescription: "just talking, not asking the computer to do anything",
        trueDescription: "asking the computer to open, search, or hand a task to Claude")

    /// Laya chooses among these; `.newClaudeSession` is a fixed phrase handled by `SessionResetRule`.
    static let choiceIntents: [RoutedIntent] = [.openApp, .webSearch, .askClaude]

    static let choiceQuestion = LayaQuestion.choice(
        "Which action should the voice assistant take for this spoken command?",
        options: choiceIntents.map { LayaQuestion.Choice($0.rawValue, description: $0.layaDescription) })

    private var manager: LayaManager?
    private var thresholds: RoutingThresholds

    public init(thresholds: RoutingThresholds = .init()) {
        self.thresholds = thresholds
    }

    public func prepare(progress: @escaping @Sendable (String) -> Void) async throws {
        guard manager == nil else { return }
        progress("Loading the Laya model (the first run downloads about 640 MB)…")
        manager = try await LayaManager.load(
            configuration: .init(lengths: [128]),
            progress: { file, bytes in progress("Downloading \(file): \(bytes / 1_000_000) MB") })
    }

    public func setThresholds(_ thresholds: RoutingThresholds) {
        self.thresholds = thresholds
    }

    public func route(_ transcript: String) async throws -> RoutingDecision {
        guard let manager else { throw RoutingError.notPrepared }
        if SessionResetRule.matches(transcript) {
            return RoutingDecision(outcome: .intent(.newClaudeSession), gateProbability: 1,
                                   choiceProbabilities: [.newClaudeSession: 1], stateWasTruncated: false)
        }
        if let intent = CommandRules.match(transcript) {
            return RoutingDecision(outcome: .intent(intent), gateProbability: 1,
                                   choiceProbabilities: [intent: 1], stateWasTruncated: false)
        }
        let gate = try await manager.answer(state: transcript, question: Self.gateQuestion)
        let gateProbability = gate.noul ?? 0
        var probabilities: [RoutedIntent: Float] = [:]
        var truncated = gate.stateWasTruncated
        if gateProbability >= thresholds.gate {
            let choice = try await manager.answer(state: transcript, question: Self.choiceQuestion)
            truncated = truncated || choice.stateWasTruncated
            for (index, intent) in Self.choiceIntents.enumerated() {
                probabilities[intent] = choice.probabilities[index]
            }
        }
        return RoutingDecision(
            outcome: RoutingPolicy.outcome(
                gateProbability: gateProbability, choiceProbabilities: probabilities, thresholds: thresholds),
            gateProbability: gateProbability,
            choiceProbabilities: probabilities,
            stateWasTruncated: truncated)
    }
}

extension RoutedIntent {
    /// Option descriptions shown to Laya. Only `choiceIntents` are ever offered; the rest come from rules.
    var layaDescription: String {
        switch self {
        case .openApp: "launch or switch to an application on the Mac"
        case .webSearch: "search the internet or look something up in the browser"
        case .askClaude: "send a coding task or question to Claude Code"
        case .newClaudeSession: "start a fresh Claude Code conversation"
        default: displayName
        }
    }
}
