import Testing
@testable import Routing

@Test(arguments: [
    "start a new claude session",
    "New Claude conversation please",
    "reset Claude and start fresh",
    "Claude, new session.",
    "clear the claude chat",
])
func recognisesAskingForAFreshClaudeSession(_ transcript: String) {
    #expect(SessionResetRule.matches(transcript))
}

@Test(arguments: [
    "tell claude to create a new file called notes",
    "ask claude to reset the session timeout in the auth module",
    "open a new safari window",
    "start a new session",
    "i had a great lunch today",
])
func leavesOtherCommandsToLaya(_ transcript: String) {
    #expect(!SessionResetRule.matches(transcript))
}

@Test func defaultChoiceThresholdSuitsThreeOptions() {
    #expect(RoutingThresholds().choice == 0.35)
}
