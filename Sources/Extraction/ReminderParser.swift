import Foundation

public struct ReminderRequest: Equatable, Sendable {
    public var title: String?
    public var due: Date?

    public init(title: String?, due: Date?) {
        self.title = title
        self.due = due
    }
}

/// "remind me to call mum at 5pm" → title "call mum", due today 17:00.
public enum ReminderParser {
    static let leadIns = ["don t let me forget to", "set a reminder to", "add a reminder to", "remind me to", "remind me"]
    static let prepositions: Set<String> = ["at", "on", "in", "by", "to"]
    static let timeWords = ["morning", "afternoon", "evening", "tonight", "night", "noon", "midnight"]
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let dayWords = ["today", "tomorrow", "tonight", "monday", "tuesday", "wednesday", "thursday", "friday",
                           "saturday", "sunday", "next", "january", "february", "march", "april", "may", "june",
                           "july", "august", "september", "october", "november", "december"]

    public static func parse(_ transcript: String, now: Date, calendar: Calendar) -> ReminderRequest {
        var text = transcript
        var due: Date?

        // 1. "in 20 minutes", "in an hour", "in half an hour"
        let relative = /\bin\s+(?:half an|an?|\d+|[a-z]+(?:-[a-z]+)?)(?:\s+and\s+a\s+half)?\s+(?:minutes?|hours?)\b/.ignoresCase()
        if let match = text.firstMatch(of: relative),
           let seconds = TimerParser.parse(String(text[match.range])).seconds {
            due = now.addingTimeInterval(TimeInterval(seconds))
            text.removeSubrange(match.range)
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                  let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let detected = match.date,
                  let range = Range(match.range, in: text) {
            // 2. NSDataDetector resolves against the real clock; keep its day offset and time, apply to `now`.
            let phrase = text[range].lowercased()
            let hasTime = phrase.contains(/\d\s*(am|pm)\b/) || phrase.contains(/\d:\d{2}/) || phrase.contains(/\bat\s+\d/)
                || timeWords.contains(where: { phrase.contains($0) })
            let hasDay = dayWords.contains(where: { phrase.contains($0) }) || phrase.contains(/\d(st|nd|rd|th)\b/)
            // A time with no day ("at 5pm") is placed on `now`'s day; the detector may already have moved it
            // to tomorrow if the real clock is past that time, which would make tests depend on the hour.
            let dayOffset = hasDay ? calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                                             to: calendar.startOfDay(for: detected)).day ?? 0 : 0
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            let hour = hasTime ? calendar.component(.hour, from: detected) : 9
            let minute = hasTime ? calendar.component(.minute, from: detected) : 0
            var result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            if hasTime, !hasDay, result < now {
                result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
            // "on friday" said on a Friday after 9 AM means next Friday, not earlier today.
            if !hasTime, result < now, weekdays.contains(where: { phrase.contains($0) }) {
                result = calendar.date(byAdding: .day, value: 7, to: result) ?? result
            }
            due = result
            text.removeSubrange(range)
        }

        var title = LeadIn.strip(text.split(separator: " ").joined(separator: " "), phrases: leadIns)
        var words = title.split(separator: " ").map(String.init)
        while let first = words.first, prepositions.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, prepositions.contains(last.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?")))
        return ReminderRequest(title: title.isEmpty ? nil : title, due: due)
    }
}
