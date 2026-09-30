import Testing
@testable import Routing

private let thresholds = RoutingThresholds()

@Test func gateBelowThresholdIsNotACommand() {
    #expect(RoutingPolicy.outcome(transcript: "open safari", gateProbability: 0.19, choiceProbabilities: [.openApp: 0.99],
                                  thresholds: thresholds) == .notACommand)
}

@Test func confidentChoiceIsTheIntent() {
    #expect(RoutingPolicy.outcome(transcript: "Ask Claude to fix the build", gateProbability: 0.9,
                                  choiceProbabilities: [.openApp: 0.1, .askClaude: 0.85, .webSearch: 0.05],
                                  thresholds: thresholds) == .intent(.askClaude))
}

@Test func weakChoiceIsAmbiguousWithTopTwo() {
    #expect(RoutingPolicy.outcome(transcript: "safari", gateProbability: 0.9,
                                  choiceProbabilities: [.openApp: 0.34, .webSearch: 0.33, .askClaude: 0.32],
                                  thresholds: thresholds) == .ambiguous([.openApp, .webSearch]))
}

@Test func missingChoiceIsNotACommand() {
    #expect(RoutingPolicy.outcome(transcript: "hmm", gateProbability: 0.9, choiceProbabilities: [:], thresholds: thresholds) == .notACommand)
}

// Speech that never names Claude must not become a Claude job, however confident Laya is.
@Test func claudeNeedsToBeNamed() {
    #expect(RoutingPolicy.outcome(transcript: "delete the source folder", gateProbability: 0.9,
                                  choiceProbabilities: [.openApp: 0.1, .askClaude: 0.85, .webSearch: 0.05],
                                  thresholds: thresholds) == .ambiguous([.askClaude, .openApp]))
    #expect(RoutingPolicy.outcome(transcript: "Claude, add a readme.", gateProbability: 0.9,
                                  choiceProbabilities: [.askClaude: 0.85, .openApp: 0.1],
                                  thresholds: thresholds) == .intent(.askClaude))
    #expect(RoutingPolicy.outcome(transcript: "claudette's recipes", gateProbability: 0.9,
                                  choiceProbabilities: [.askClaude: 0.85, .webSearch: 0.1],
                                  thresholds: thresholds) == .ambiguous([.askClaude, .webSearch]))
}

@Test func outcomesHaveStableLogNames() {
    #expect(RoutingDecision.Outcome.intent(.webSearch).logName == "web_search")
    #expect(RoutingDecision.Outcome.notACommand.logName == "not_a_command")
    #expect(RoutingDecision.Outcome.ambiguous([.openApp]).logName == "ambiguous")
}
