import Foundation

public struct RelayTimer: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String?
    public let endsAt: Date

    public init(id: UUID, name: String?, endsAt: Date) {
        self.id = id
        self.name = name
        self.endsAt = endsAt
    }
}

public struct TimerStart: Sendable, Equatable {
    public let timer: RelayTimer
    public let notificationsAllowed: Bool

    public init(timer: RelayTimer, notificationsAllowed: Bool) {
        self.timer = timer
        self.notificationsAllowed = notificationsAllowed
    }
}

/// Typing, notes, reminders and timers. A protocol so the assistant can be tested with a fake.
public protocol CaptureControlling: Sendable {
    /// Pastes `text` into the app in front and returns that app's name.
    func typeText(_ text: String) async throws -> String
    func addNote(_ text: String) async throws
    func addReminder(title: String, due: Date?) async throws
    func startTimer(name: String?, seconds: Int) async throws -> TimerStart
    func activeTimers() async -> [RelayTimer]
    func cancelTimer(id: UUID) async
}
