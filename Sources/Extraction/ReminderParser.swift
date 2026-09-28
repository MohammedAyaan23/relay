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
        let relative = /\bin\s+(?:half an|an?|\d+(?:\.\d+)?|[a-z]+(?:-[a-z]+)?)(?:\s+and\s+a\s+half)?\s+(?:minutes?|hours?|days?|weeks?)\b/.ignoresCase()
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
            let hasMeridiem = phrase.contains(/\d\s*[ap]\.?\s?m(\b|\.)/)
            let hasTime = hasMeridiem || phrase.contains(/\d:\d{2}/) || phrase.contains(/\bat\s+\d/)
                || phrase.contains(/o.?clock/) || timeWords.contains(where: { phrase.contains($0) })
            let hasDay = dayWords.contains(where: { phrase.contains($0) }) || phrase.contains(/\d(st|nd|rd|th)\b/)
            // A time with no day ("at 5pm") is placed on `now`'s day; the detector may already have moved it
            // to tomorrow if the real clock is past that time, which would make tests depend on the hour.
            let dayOffset = hasDay ? calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                                             to: calendar.startOfDay(for: detected)).day ?? 0 : 0
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            var hour = hasTime ? calendar.component(.hour, from: detected) : 9
            // "the 2 o'clock match" with no am/pm means the afternoon.
            if hasTime, !hasMeridiem, (1...6).contains(hour) { hour += 12 }
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
        } else if let match = text.firstMatch(of: /\bat\s+(\d{1,2})(?::(\d{2}))?\b/),
                  let spokenHour = Int(match.output.1), (1...12).contains(spokenHour) {
            // A bare "at 8": NSDataDetector ignores it, so pick the sensible next 8 o'clock.
            let minute = match.output.2.flatMap { Int($0) } ?? 0
            due = nextOccurrence(ofSpokenHour: spokenHour, minute: minute, after: now, calendar: calendar)
            text.removeSubrange(match.range)
        }

        // Never set a reminder that is already due.
        if let date = due, date <= now { due = nil }

        var title = LeadIn.strip(text.split(separator: " ").joined(separator: " "), phrases: leadIns)
        var words = title.split(separator: " ").map(String.init)
        while let first = words.first, prepositions.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, prepositions.contains(last.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?")))
        return ReminderRequest(title: title.isEmpty ? nil : title, due: due)
    }

    /// 1–6 means the afternoon ("at 3" → 15:00); 7–11 means whichever of morning or evening comes next;
    /// 12 is noon. A time already gone today moves to tomorrow.
    static func nextOccurrence(ofSpokenHour spokenHour: Int, minute: Int, after now: Date, calendar: Calendar) -> Date? {
        func today(_ hour: Int) -> Date? { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) }
        let candidates: [Int] = switch spokenHour {
        case 12: [12]
        case 1...6: [spokenHour + 12]
        default: [spokenHour, spokenHour + 12]
        }
        if let upcoming = candidates.compactMap(today).first(where: { $0 > now }) { return upcoming }
        return today(candidates[0]).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
    }
}
