import Foundation
import Testing
@testable import Extraction

@Test(arguments: [
    ("type see you soon.", "see you soon."),
    ("Type: Hello, World!", "Hello, World!"),
    ("write thank you so much", "thank you so much"),
    ("write down my address", "my address"),
    ("type out I'm on my way", "I'm on my way"),
    ("dictate thanks, I'll review it today.", "thanks, I'll review it today."),
    ("please type hello", "hello"),
])
func dictationKeepsWordingAndPunctuation(_ transcript: String, _ expected: String) {
    #expect(DictationParser.text(from: transcript) == expected)
}

@Test func emptyDictationIsNil() {
    #expect(DictationParser.text(from: "type") == nil)
    #expect(DictationParser.text(from: "write:") == nil)
}

@Test(arguments: [
    ("note that the car needs servicing", "the car needs servicing"),
    ("take a note that the wifi password is on the fridge", "the wifi password is on the fridge"),
    ("note down buy milk and eggs", "buy milk and eggs"),
    ("add a note saying call the bank", "call the bank"),
    ("jot down this idea", "this idea"),
])
func noteTextDropsTheLeadIn(_ transcript: String, _ expected: String) {
    #expect(NoteParser.text(from: transcript) == expected)
}

@Test func emptyNoteIsNil() {
    #expect(NoteParser.text(from: "take a note") == nil)
}

// Reminders — "now" is fixed at 16:00 today in the Mac's calendar and time zone.
private let calendar = Calendar.current
private let now = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!

private func at(_ hour: Int, _ minute: Int = 0, daysFromNow days: Int = 0) -> Date {
    let day = calendar.date(byAdding: .day, value: days, to: now)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

@Test func reminderAtALaterTimeToday() {
    #expect(ReminderParser.parse("remind me to call mum at 5pm", now: now, calendar: calendar)
        == ReminderRequest(title: "call mum", due: at(17)))
}

@Test func reminderAtATimeAlreadyPassedMovesToTomorrow() {
    #expect(ReminderParser.parse("remind me at 3pm to call the bank", now: now, calendar: calendar)
        == ReminderRequest(title: "call the bank", due: at(15, daysFromNow: 1)))
}

@Test func reminderTomorrowAtNine() {
    #expect(ReminderParser.parse("remind me tomorrow at 9 to pay rent", now: now, calendar: calendar)
        == ReminderRequest(title: "pay rent", due: at(9, daysFromNow: 1)))
}

@Test func reminderInTwentyMinutes() {
    #expect(ReminderParser.parse("remind me to stretch in 20 minutes", now: now, calendar: calendar)
        == ReminderRequest(title: "stretch", due: now.addingTimeInterval(1200)))
    #expect(ReminderParser.parse("remind me in half an hour to check the oven", now: now, calendar: calendar)
        == ReminderRequest(title: "check the oven", due: now.addingTimeInterval(1800)))
}

@Test func reminderWithoutATime() {
    #expect(ReminderParser.parse("remind me to buy milk", now: now, calendar: calendar)
        == ReminderRequest(title: "buy milk", due: nil))
    #expect(ReminderParser.parse("don't let me forget to water the plants", now: now, calendar: calendar)
        == ReminderRequest(title: "water the plants", due: nil))
    #expect(ReminderParser.parse("remind me", now: now, calendar: calendar).title == nil)
}

/// Weekday phrases are resolved by NSDataDetector against the real clock, so this uses the real "now".
@Test func reminderOnADayWithoutATimeIsNineAM() throws {
    let realNow = Date()
    let request = ReminderParser.parse("remind me on friday to submit the report", now: realNow, calendar: calendar)
    #expect(request.title == "submit the report")
    let due = try #require(request.due)
    #expect(calendar.component(.weekday, from: due) == 6)
    #expect(calendar.component(.hour, from: due) == 9)
    #expect(due > realNow)
}

@Test(arguments: [
    ("set a timer for 10 minutes", TimerRequest(seconds: 600, name: nil)),
    ("set a pasta timer for 9 minutes", TimerRequest(seconds: 540, name: "pasta")),
    ("start a 25 minute pomodoro timer", TimerRequest(seconds: 1500, name: "pomodoro")),
    ("pomodoro", TimerRequest(seconds: 1500, name: "pomodoro")),
    ("timer for an hour and a half", TimerRequest(seconds: 5400, name: nil)),
    ("timer for half an hour", TimerRequest(seconds: 1800, name: nil)),
    ("set a timer for 1 hour 20 minutes", TimerRequest(seconds: 4800, name: nil)),
    ("timer for 90 seconds", TimerRequest(seconds: 90, name: nil)),
    ("tea timer for forty-five seconds", TimerRequest(seconds: 45, name: "tea")),
    ("set a ten minute timer", TimerRequest(seconds: 600, name: nil)),
    ("start a timer", TimerRequest(seconds: nil, name: nil)),
])
func timerRequests(_ transcript: String, _ expected: TimerRequest) {
    #expect(TimerParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("cancel the pasta timer", TimerTarget.named("pasta")),
    ("how long is left on the tea timer", .named("tea")),
    ("cancel the timer", .unspecified),
    ("how long is left on the timer", .unspecified),
    ("cancel all timers", .all),
    ("stop every timer", .all),
])
func timerTargets(_ transcript: String, _ expected: TimerTarget) {
    #expect(TimerParser.target(transcript) == expected)
}

// MARK: Final-review findings

@Test func reminderTimesSpokenInOtherWays() {
    #expect(ReminderParser.parse("remind me to leave at 5 p.m.", now: now, calendar: calendar)
        == ReminderRequest(title: "leave", due: at(17)))
    #expect(ReminderParser.parse("remind me at 8 to take pills", now: now, calendar: calendar)
        == ReminderRequest(title: "take pills", due: at(20)))
    #expect(ReminderParser.parse("remind me to buy milk at 3", now: now, calendar: calendar)
        == ReminderRequest(title: "buy milk", due: at(15, daysFromNow: 1)))
    #expect(ReminderParser.parse("remind me to watch the 2 o'clock match", now: now, calendar: calendar).due
        == at(14, daysFromNow: 1))
}

@Test func reminderInDaysAndDecimalHours() {
    #expect(ReminderParser.parse("remind me in 2 days to pay rent", now: now, calendar: calendar)
        == ReminderRequest(title: "pay rent", due: now.addingTimeInterval(2 * 86_400)))
    #expect(ReminderParser.parse("remind me in 1.5 hours to leave", now: now, calendar: calendar)
        == ReminderRequest(title: "leave", due: now.addingTimeInterval(5400)))
}

@Test func remindersAreNeverDueInThePast() {
    let late = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
    #expect(ReminderParser.parse("remind me tonight to lock up", now: late, calendar: calendar)
        == ReminderRequest(title: "lock up", due: nil))
    for phrase in ["remind me at 5 p.m. to go", "remind me at 8 to go", "remind me at 3pm to go", "remind me tonight to go",
                   "remind me in 2 days to go", "remind me to go at noon"] {
        let due = ReminderParser.parse(phrase, now: late, calendar: calendar).due
        #expect(due == nil || due! > late, "\(phrase)")
    }
}

@Test(arguments: [
    ("set a timer for 1.5 hours", 5400),
    ("timer for 1.5 minutes", 90),
    ("timer for 1 1/2 hours", 5400),
    ("timer for 2 and a half minutes", 150),
])
func fractionalTimerDurations(_ transcript: String, _ seconds: Int) {
    #expect(TimerParser.parse(transcript).seconds == seconds)
}

// Absurd durations must be refused, not crash Relay (Int overflow traps).
@Test func hugeTimerDurationsAreRefused() {
    #expect(TimerParser.parse("set a timer for 99999999999999999999 weeks").seconds == nil)
    #expect(TimerParser.parse("set a timer for one quintillion weeks").seconds == nil)
    #expect(TimerParser.parse("set a timer for 9 minutes").seconds == 540)
}

@Test func hugeReminderDelaysAreRefused() {
    let request = ReminderParser.parse("remind me in 99999999999999999999 weeks to stretch", now: now, calendar: calendar)
    #expect(request.due == nil)
}
