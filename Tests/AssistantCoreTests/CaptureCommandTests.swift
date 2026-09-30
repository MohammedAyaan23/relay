import Foundation
import Testing
@testable import AssistantCore
@testable import Routing
@testable import SystemControls

private func timer(_ name: String?, in seconds: TimeInterval) -> RelayTimer {
    RelayTimer(id: UUID(), name: name, endsAt: Date().addingTimeInterval(seconds))
}

// MARK: Typing

@MainActor @Test func typesTheDictatedText() async {
    let h = Harness(transcript: "type see you soon.", outcome: .intent(.typeText))
    await h.speak()
    #expect(await h.capture.calls == ["type(see you soon.)"])
    #expect(h.assistant.message == "Typed into TextEdit")
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func typingProblems() async {
    let e = Harness(transcript: "type", outcome: .intent(.typeText))
    await e.speak()
    #expect(e.assistant.message == "What should I type?")

    let n = Harness(transcript: "type hello", outcome: .intent(.typeText))
    await n.capture.fail(with: .noFrontWindow)
    await n.speak()
    #expect(n.assistant.message == "There's no app window in front to type into.")
}

// MARK: Notes

@MainActor @Test func savesANote() async {
    let h = Harness(transcript: "note that the car needs servicing", outcome: .intent(.addNote))
    await h.speak()
    #expect(await h.capture.calls == ["note(the car needs servicing)"])
    #expect(h.assistant.message == "Noted: the car needs servicing")
}

@MainActor @Test func longNotesAreShortenedInThePill() async {
    let text = String(repeating: "a", count: 50)
    let h = Harness(transcript: "note that \(text)", outcome: .intent(.addNote))
    await h.speak()
    #expect(h.assistant.message == "Noted: \(String(repeating: "a", count: 40))…")
}

@MainActor @Test func noteProblems() async {
    let e = Harness(transcript: "take a note", outcome: .intent(.addNote))
    await e.speak()
    #expect(e.assistant.message == "What should the note say?")

    let d = Harness(transcript: "note that x", outcome: .intent(.addNote))
    await d.capture.fail(with: .automationDenied("Notes"))
    await d.speak()
    #expect(d.assistant.message == "Relay needs permission to control Notes to save notes.")
    #expect(d.assistant.missingPermission == .automation)

    let f = Harness(transcript: "note that x", outcome: .intent(.addNote))
    await f.capture.fail(with: .failed("timed out"))
    await f.speak()
    #expect(f.assistant.message == "Couldn't save the note: timed out")
}

// MARK: Reminders

@MainActor @Test func remindersWithAndWithoutATime() async {
    let plain = Harness(transcript: "remind me to buy milk", outcome: .intent(.addReminder))
    await plain.speak()
    #expect(await plain.capture.calls == ["reminder(buy milk, due: false)"])
    #expect(plain.assistant.message == "Reminder added: buy milk")

    let timed = Harness(transcript: "remind me tomorrow at 9 to pay rent", outcome: .intent(.addReminder))
    await timed.speak()
    #expect(await timed.capture.calls == ["reminder(pay rent, due: true)"])
    #expect(timed.assistant.message == "Reminder set: pay rent — tomorrow 9:00 AM")
}

@MainActor @Test func reminderProblems() async {
    let e = Harness(transcript: "remind me", outcome: .intent(.addReminder))
    await e.speak()
    #expect(e.assistant.message == "What should I remind you about?")

    let d = Harness(transcript: "remind me to call", outcome: .intent(.addReminder))
    await d.capture.fail(with: .remindersDenied)
    await d.speak()
    #expect(d.assistant.message == "Relay needs Reminders access to add reminders.")
    #expect(d.assistant.missingPermission == .reminders)

    let f = Harness(transcript: "remind me to call", outcome: .intent(.addReminder))
    await f.capture.fail(with: .failed("no default Reminders list"))
    await f.speak()
    #expect(f.assistant.message == "Couldn't add the reminder: no default Reminders list")
}

// MARK: Timers

@MainActor @Test func startsNamedAndUnnamedTimers() async {
    let p = Harness(transcript: "set a pasta timer for 9 minutes", outcome: .intent(.startTimer))
    await p.speak()
    #expect(await p.capture.calls == ["start(pasta, 540)"])
    #expect(p.assistant.message == "Pasta timer set for 9 minutes")
    #expect(p.assistant.timers.count == 1)

    let u = Harness(transcript: "set a timer for 10 minutes", outcome: .intent(.startTimer))
    await u.speak()
    #expect(u.assistant.message == "Timer set for 10 minutes")
}

@MainActor @Test func timerWithNotificationsOffSaysSo() async {
    let h = Harness(transcript: "set a timer for 10 minutes", outcome: .intent(.startTimer))
    await h.capture.setNotificationsAllowed(false)
    await h.speak()
    #expect(h.assistant.message
        == "Timer set for 10 minutes, but notifications are off for Relay, so turn them on to hear it")
}

@MainActor @Test func timerWithoutADurationAsks() async {
    let h = Harness(transcript: "start a timer", outcome: .intent(.startTimer))
    await h.speak()
    #expect(h.assistant.message == "How long? Try “10 minutes”.")
}

@MainActor @Test func timeLeft() async {
    let none = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await none.speak()
    #expect(none.assistant.message == "No timers running")

    let one = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await one.capture.setRunning([timer(nil, in: 7200.5)])
    await one.speak()
    #expect(one.assistant.message == "2 hours left")

    let many = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await many.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await many.speak()
    #expect(many.assistant.message == "Pasta: 3 min left · Tea: <1 min left")

    let named = Harness(transcript: "how long is left on the soup timer", outcome: .intent(.timerStatus))
    await named.capture.setRunning([timer("pasta", in: 150)])
    await named.speak()
    #expect(named.assistant.message == "No soup timer running")
}

@MainActor @Test func cancellingTimers() async {
    let named = Harness(transcript: "cancel the pasta timer", outcome: .intent(.cancelTimer))
    await named.capture.setRunning([timer("pasta", in: 150), timer("pasta 2", in: 300), timer("tea", in: 30)])
    await named.speak()
    #expect(await named.capture.calls == ["cancel(pasta)"])
    #expect(named.assistant.message == "Cancelled the pasta timer")
    #expect(named.assistant.timers.count == 2)

    let which = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await which.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await which.speak()
    #expect(which.assistant.message == "Which timer? Pasta, Tea")

    let only = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await only.capture.setRunning([timer(nil, in: 30)])
    await only.speak()
    #expect(only.assistant.message == "Cancelled the timer")

    let all = Harness(transcript: "cancel all timers", outcome: .intent(.cancelTimer))
    await all.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await all.speak()
    #expect(all.assistant.message == "Cancelled 2 timers")

    let unknown = Harness(transcript: "cancel the soup timer", outcome: .intent(.cancelTimer))
    await unknown.capture.setRunning([timer("pasta", in: 150)])
    await unknown.speak()
    #expect(unknown.assistant.message == "No soup timer running")

    let none = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await none.speak()
    #expect(none.assistant.message == "No timers running")
}

@MainActor @Test func panelCancelAndRefresh() async {
    let h = Harness()
    let tea = timer("tea", in: 60)
    await h.capture.setRunning([tea])
    await h.assistant.refreshTimers()
    #expect(h.assistant.timers == [tea])
    await h.assistant.cancelTimer(tea)
    #expect(h.assistant.timers.isEmpty)
}

// MARK: Formatting

@Test func remainingTimeFormats() {
    let now = Date()
    #expect(CaptureFormat.remaining([], now: now) == "No timers running")
    #expect(CaptureFormat.remaining([RelayTimer(id: UUID(), name: nil, endsAt: now.addingTimeInterval(432))], now: now)
        == "7 minutes 12 seconds left")
    #expect(CaptureFormat.displayName(RelayTimer(id: UUID(), name: "pasta 2", endsAt: now)) == "Pasta 2")
}

@Test func reminderTimesReadNaturally() {
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 28; components.hour = 16
    let now = calendar.date(from: components)! // a Monday
    func at(_ days: Int, _ hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: days, to: now)!)!
    }
    #expect(CaptureFormat.reminderTime(at(0, 17), now: now, calendar: calendar) == "today 5:00 PM")
    #expect(CaptureFormat.reminderTime(at(1, 9), now: now, calendar: calendar) == "tomorrow 9:00 AM")
    #expect(CaptureFormat.reminderTime(at(4, 9), now: now, calendar: calendar) == "Fri 9:00 AM")
    #expect(CaptureFormat.reminderTime(at(10, 9), now: now, calendar: calendar) == "Oct 8 9:00 AM")
}

// A timers.json edited to hold an absurd end date must not crash "how long is left".
@Test func absurdTimerEndDoesNotCrash() {
    let timer = RelayTimer(id: UUID(), name: "odd", endsAt: Date(timeIntervalSinceReferenceDate: 1e300))
    #expect(CaptureFormat.remaining([timer], now: Date()).hasSuffix("left"))
}
