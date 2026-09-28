import AppKit
import EventKit
import Foundation

/// The real implementation: clipboard + ⌘V, Notes via osascript, EventKit reminders, scheduled timers.
public final class MacCaptureControls: CaptureControlling {
    private let runner: any CommandRunning
    private let timers: TimerStore
    private let scheduler: any NotificationScheduling

    public init(runner: any CommandRunning = ProcessRunner(),
                timers: TimerStore = TimerStore(fileURL: TimerStore.defaultFileURL),
                scheduler: any NotificationScheduling = UserNotificationScheduler()) {
        self.runner = runner
        self.timers = timers
        self.scheduler = scheduler
    }

    // MARK: Typing

    public func typeText(_ text: String) async throws -> String {
        try Permissions.requireAccessibility()
        let (app, snapshot, changeCount) = try await MainActor.run { () throws -> (String, PasteboardSwap.Snapshot, Int) in
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != Bundle.main.bundleIdentifier else { throw SystemControlError.noFrontWindow }
            if NSApp.keyWindow != nil { _ = front.activate() } // don't paste into Relay's own panel
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSwap.snapshot(of: pasteboard)
            let changeCount = PasteboardSwap.write(text, to: pasteboard)
            KeyEvents.pressKey(9 /* kVK_ANSI_V */, flags: .maskCommand)
            return (front.localizedName ?? "the front app", snapshot, changeCount)
        }
        try? await Task.sleep(for: .milliseconds(300)) // let the app read the clipboard first
        await MainActor.run { _ = PasteboardSwap.restore(snapshot, to: .general, ifChangeCount: changeCount) }
        return app
    }

    // MARK: Notes

    public func addNote(_ text: String) async throws {
        let body = try NoteScript.interpret(try await runner.run("/usr/bin/osascript", NoteScript.readArguments()))
        let updated = NoteBody.prepend(entry: text, at: Date(), to: body)
        _ = try NoteScript.interpret(try await runner.run("/usr/bin/osascript", NoteScript.writeArguments(body: updated)))
    }

    // MARK: Reminders

    public func addReminder(title: String, due: Date?) async throws {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { throw SystemControlError.remindersDenied }
        guard let list = store.defaultCalendarForNewReminders() else {
            throw SystemControlError.failed("no default Reminders list")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw SystemControlError.failed(error.localizedDescription)
        }
    }

    // MARK: Timers

    public func startTimer(name: String?, seconds: Int) async throws -> TimerStart {
        let timer = try timers.start(name: name, seconds: seconds, now: Date())
        let title = timer.name.map { $0.prefix(1).uppercased() + $0.dropFirst() + " timer done" } ?? "Timer done"
        do {
            try await scheduler.schedule(id: timer.id.uuidString, title: title,
                                         body: "\(DurationText.describe(seconds)) is up", after: TimeInterval(seconds))
        } catch {
            // The timer is still saved; the assistant tells the user notifications are off.
        }
        return TimerStart(timer: timer, notificationsAllowed: await scheduler.allowed())
    }

    public func activeTimers() async -> [RelayTimer] {
        timers.active(now: Date())
    }

    public func cancelTimer(id: UUID) async {
        try? timers.remove(id: id)
        await scheduler.cancel(id: id.uuidString)
    }

    /// Removes ended timers; called at launch.
    public func pruneTimers() {
        try? timers.prune(now: Date())
    }
}
