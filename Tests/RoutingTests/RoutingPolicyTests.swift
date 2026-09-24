import Testing
@testable import Routing

private let thresholds = RoutingThresholds()

@Test func gateBelowThresholdIsNotACommand() {
    #expect(RoutingPolicy.outcome(gateProbability: 0.19, choiceProbabilities: [.openApp: 0.99],
                                  thresholds: thresholds) == .notACommand)
}

@Test func confidentChoiceIsTheIntent() {
    #expect(RoutingPolicy.outcome(gateProbability: 0.9,
                                  choiceProbabilities: [.openApp: 0.1, .askClaude: 0.85, .webSearch: 0.05],
                                  thresholds: thresholds) == .intent(.askClaude))
}

@Test func weakChoiceIsAmbiguousWithTopTwo() {
    #expect(RoutingPolicy.outcome(gateProbability: 0.9,
                                  choiceProbabilities: [.openApp: 0.34, .webSearch: 0.33, .askClaude: 0.33],
                                  thresholds: thresholds) == .ambiguous([.openApp, .webSearch]))
}

@Test func missingChoiceIsNotACommand() {
    #expect(RoutingPolicy.outcome(gateProbability: 0.9, choiceProbabilities: [:], thresholds: thresholds) == .notACommand)
}

@Test func outcomesHaveStableLogNames() {
    #expect(RoutingDecision.Outcome.intent(.webSearch).logName == "web_search")
    #expect(RoutingDecision.Outcome.notACommand.logName == "not_a_command")
    #expect(RoutingDecision.Outcome.ambiguous([.openApp]).logName == "ambiguous")
}
