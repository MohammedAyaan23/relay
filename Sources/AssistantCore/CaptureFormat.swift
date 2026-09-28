import Foundation
import SystemControls

/// Wording for timers and reminders in the pill and panel.
public enum CaptureFormat {
    public static func duration(_ seconds: Int) -> String {
        DurationText.describe(seconds)
    }

    /// "Pasta 2", or "Timer" for an unnamed timer.
    public static func displayName(_ timer: RelayTimer) -> String {
        guard let name = timer.name else { return "Timer" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// One timer: "7 minutes 12 seconds left". Several: "Pasta: 3 min left · Tea: <1 min left".
    public static func remaining(_ timers: [RelayTimer], now: Date) -> String {
        guard !timers.isEmpty else { return "No timers running" }
        func secondsLeft(_ timer: RelayTimer) -> Int { max(0, Int(timer.endsAt.timeIntervalSince(now).rounded(.up))) }
        if timers.count == 1 { return "\(duration(secondsLeft(timers[0]))) left" }
        return timers.map { timer in
            let seconds = secondsLeft(timer)
            let minutes = seconds < 60 ? "<1 min" : "\(Int((Double(seconds) / 60).rounded(.up))) min"
            return "\(displayName(timer)): \(minutes) left"
        }.joined(separator: " · ")
    }

    /// "today 5:00 PM", "tomorrow 9:00 AM", "Fri 9:00 AM" within the week, otherwise "Oct 3 9:00 AM".
    public static func reminderTime(_ due: Date, now: Date, calendar: Calendar) -> String {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: due)
        }
        let time = format("h:mm a")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "today \(time)"
        case 1: return "tomorrow \(time)"
        case 2...6: return "\(format("EEE")) \(time)"
        default: return "\(format("MMM d")) \(time)"
        }
    }
}
