import Foundation
import UserNotifications

/// Schedules the notification that ends a timer. macOS delivers it even if Relay has quit.
public protocol NotificationScheduling: Sendable {
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws
    func cancel(id: String) async
    func allowed() async -> Bool
}

public struct UserNotificationScheduler: NotificationScheduling {
    public init() {}

    public func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    public func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
