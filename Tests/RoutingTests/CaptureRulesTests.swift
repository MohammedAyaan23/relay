import Testing
@testable import Routing

@Test(arguments: [
    ("type see you soon", RoutedIntent.typeText),
    ("dictate thanks for the update", .typeText),
    ("write thank you so much", .typeText),
    ("take a note that the wifi password is on the fridge", .addNote),
    ("note down buy milk", .addNote),
    ("remind me to call mum at 5pm", .addReminder),
    ("don't let me forget to water the plants", .addReminder),
    ("set a timer for 10 minutes", .startTimer),
    ("25 minute pomodoro", .startTimer),
    ("how long is left on the timer", .timerStatus),
    ("how much time is left on the pasta timer", .timerStatus),
    ("cancel the pasta timer", .cancelTimer),
    ("stop the timer", .cancelTimer),
])
func captureCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("type i'll be there in ten minutes", RoutedIntent.typeText),
    ("write thank you so much", .typeText),
    ("note that the car needs servicing", .addNote),
    ("remind me at 8pm to take my medicine", .addReminder),
    ("remind me on friday to submit the report", .addReminder),
    ("timer for 3 minutes", .startTimer),
])
func heldOutCapturePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    ("type turn the volume down", RoutedIntent.typeText),
    ("remind me to lock the door", .addReminder),
    ("note that the tab is broken", .addNote),
    ("please remind me to close the window", .addReminder),
])
func captureWinsOverDeviceWords(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test func claudeRequestsStayWithLaya() {
    #expect(CommandRules.match("tell claude to write tests") == nil)
    #expect(CommandRules.match("open the reminders app") == nil)
}

// MARK: Final-review findings

@Test(arguments: ["delete my dentist reminder", "what's my next reminder", "the reminder app is broken"])
func talkingAboutRemindersDoesNotCreateOne(_ transcript: String) {
    #expect(CommandRules.match(transcript) != .addReminder)
}

@Test(arguments: ["set a reminder to call mum", "add a reminder for the dentist", "remind me to stretch"])
func askingForAReminderStillWorks(_ transcript: String) {
    #expect(CommandRules.match(transcript) == .addReminder)
}
