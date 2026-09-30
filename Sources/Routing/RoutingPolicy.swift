/// Turns model probabilities into a decision. Kept separate from the model so it can be unit-tested.
public enum RoutingPolicy {
    public static func outcome(
        transcript: String, gateProbability: Float, choiceProbabilities: [RoutedIntent: Float],
        thresholds: RoutingThresholds
    ) -> RoutingDecision.Outcome {
        guard gateProbability >= thresholds.gate else { return .notACommand }
        let ranked = choiceProbabilities.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return .notACommand }
        if top.value < thresholds.choice { return .ambiguous(ranked.prefix(2).map(\.key)) }
        // A Claude job edits files in the project, so it needs Claude named, not just Laya's guess.
        if top.key == .askClaude, !mentionsClaude(transcript) { return .ambiguous(ranked.prefix(2).map(\.key)) }
        return .intent(top.key)
    }

    static func mentionsClaude(_ transcript: String) -> Bool {
        transcript.lowercased().split(whereSeparator: { !$0.isLetter }).contains("claude")
    }
}
