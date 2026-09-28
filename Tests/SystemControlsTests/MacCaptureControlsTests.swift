import Foundation
import Testing
@testable import SystemControls

actor FakeScheduler: NotificationScheduling {
    private(set) var scheduled: [(id: String, title: String, body: String, after: TimeInterval)] = []
    private(set) var cancelled: [String] = []
    var isAllowed = true
    var failSchedule = false

    func setAllowed(_ value: Bool) { isAllowed = value }
    func setFailSchedule(_ value: Bool) { failSchedule = value }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws {
        if failSchedule { throw SystemControlError.failed("not allowed") }
        scheduled.append((id, title, body, seconds))
    }
    func cancel(id: String) async { cancelled.append(id) }
    func allowed() async -> Bool { isAllowed }
}

private func store() -> TimerStore {
    TimerStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)/timers.json"))
}

@Test func startingATimerSchedulesItsNotification() async throws {
    let scheduler = FakeScheduler()
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "pasta", seconds: 540)
    #expect(start.timer.name == "pasta")
    #expect(start.notificationsAllowed)
    let scheduled = await scheduler.scheduled
    #expect(scheduled.count == 1)
    #expect(scheduled[0].id == start.timer.id.uuidString)
    #expect(scheduled[0].title == "Pasta timer done")
    #expect(scheduled[0].body == "9 minutes is up")
    #expect(scheduled[0].after == 540)
    #expect(await controls.activeTimers().map(\.id) == [start.timer.id])
}

@Test func unnamedTimerNotificationSaysTimerDone() async throws {
    let scheduler = FakeScheduler()
    _ = try await MacCaptureControls(timers: store(), scheduler: scheduler).startTimer(name: nil, seconds: 60)
    #expect(await scheduler.scheduled.first?.title == "Timer done")
}

@Test func timerIsKeptWhenNotificationsAreOff() async throws {
    let scheduler = FakeScheduler()
    await scheduler.setFailSchedule(true)
    await scheduler.setAllowed(false)
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "tea", seconds: 60)
    #expect(!start.notificationsAllowed)
    #expect(await controls.activeTimers().count == 1)
}

@Test func cancellingATimerRemovesItAndItsNotification() async throws {
    let scheduler = FakeScheduler()
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "tea", seconds: 60)
    await controls.cancelTimer(id: start.timer.id)
    #expect(await controls.activeTimers().isEmpty)
    #expect(await scheduler.cancelled == [start.timer.id.uuidString])
}

@Test func addingANoteReadsThenWritesTheRelayNote() async throws {
    let mine = "<div><h1>Relay</h1></div><div><i>Voice notes from Relay</i></div><div>Sep 27, 09:00 — old</div>"
    let runner = FakeRunner(installed: [])
    await runner.setRunResult(CommandResult(status: 0, stdout: "id-mine\u{1f}0\u{1f}\(mine)\u{1e}\n", stderr: ""))
    try await MacCaptureControls(runner: runner, timers: store(), scheduler: FakeScheduler()).addNote("buy milk")
    let calls = await runner.calls
    #expect(calls.count == 2)
    #expect(calls.allSatisfy { $0.first == "/usr/bin/osascript" })
    let write = try #require(calls.last)
    #expect(write.last == "id-mine")
    #expect(write[write.count - 2].contains("— buy milk</div><div>Sep 27, 09:00 — old</div>"))
}

@Test func withoutRelaysOwnNoteANewOneIsCreated() async throws {
    let runner = FakeRunner(installed: [])
    await runner.setRunResult(CommandResult(status: 0, stdout: "id-user\u{1f}0\u{1f}<div><h1>Relay</h1></div><div>mine</div>\u{1e}\n", stderr: ""))
    try await MacCaptureControls(runner: runner, timers: store(), scheduler: FakeScheduler()).addNote("buy milk")
    let write = try #require(await runner.calls.last)
    #expect(write.last == "") // empty id → make a new note; the user's own "Relay" note is untouched
}
