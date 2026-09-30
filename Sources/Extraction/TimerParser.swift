import Foundation

public struct TimerRequest: Equatable, Sendable {
    public var seconds: Int?
    public var name: String?

    public init(seconds: Int?, name: String?) {
        self.seconds = seconds
        self.name = name
    }
}

public enum TimerTarget: Equatable, Sendable {
    case all
    case named(String)
    case unspecified
}

/// "set a pasta timer for 9 minutes" → 540 seconds, named "pasta".
public enum TimerParser {
    static let units: [String: Int] = ["hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600,
                                       "minute": 60, "minutes": 60, "min": 60, "mins": 60,
                                       "second": 1, "seconds": 1, "sec": 1, "secs": 1,
                                       "day": 86_400, "days": 86_400, "week": 604_800, "weeks": 604_800]
    static let nameStopWords: Set<String> = ["a", "an", "the", "my", "set", "start", "new", "for", "me", "timer",
                                             "cancel", "stop", "delete", "clear", "remove", "on", "left", "is",
                                             "how", "long", "much", "time", "all", "every", "of", "and", "half"]

    static let maxSeconds = 10.0 * 365 * 86_400

    public static func parse(_ transcript: String) -> TimerRequest {
        let words = tokens(transcript)
        var seconds = 0.0 // added up as Double so absurd spoken numbers can't overflow Int
        var found = false
        for (i, word) in words.enumerated() {
            guard let unit = units[word] else { continue }
            if i >= 2, words[i - 2] == "half", words[i - 1] == "an" || words[i - 1] == "a" {
                seconds += Double(unit / 2)
                found = true
            } else if let amount = amount(before: i, in: words) {
                seconds += (amount * Double(unit)).rounded()
                found = true
            }
            if i + 3 < words.count, words[i + 1] == "and", words[i + 2] == "a", words[i + 3] == "half" {
                seconds += Double(unit / 2)
            }
        }
        if !found, words.contains("pomodoro") {
            seconds = 1500
            found = true
        }
        var name = nameBeforeTimer(words)
        if name == nil, words.contains("pomodoro") { name = "pomodoro" }
        // Anything over 10 years is a misheard number, not a real timer or reminder.
        let valid = found && seconds.isFinite && seconds >= 0 && seconds <= maxSeconds
        return TimerRequest(seconds: valid ? Int(seconds) : nil, name: name)
    }

    public static func target(_ transcript: String) -> TimerTarget {
        let words = tokens(transcript)
        if words.contains("all") || words.contains("every") { return .all }
        if let name = nameBeforeTimer(words) { return .named(name) }
        return .unspecified
    }

    /// Lowercased words, keeping decimals ("1.5") and fractions ("1/2") whole.
    static func tokens(_ transcript: String) -> [String] {
        transcript.lowercased().matches(of: /\d+\/\d+|\d+(?:\.\d+)?|[a-z]+/).map { String($0.output) }
    }

    /// The amount before a unit: "1.5", "1 1/2", "2 and a half", "a", or a spelled number
    /// (hyphenated first: "forty five" parses as 4005 when spaced).
    static func amount(before index: Int, in words: [String]) -> Double? {
        guard index >= 1 else { return nil }
        let previous = words[index - 1]
        if previous == "half", index >= 4, words[index - 2] == "a", words[index - 3] == "and",
           let whole = number(words[index - 4]) {
            return whole + 0.5
        }
        if let fraction = fraction(previous) {
            if index >= 2, let whole = Double(words[index - 2]) { return whole + fraction }
            return fraction
        }
        if let value = Double(previous) { return value }
        if previous == "a" || previous == "an" { return 1 }
        if index >= 2, let value = NumberFormatter.spellOutNumber("\(words[index - 2])-\(previous)") { return Double(value) }
        return NumberFormatter.spellOutNumber(previous).map(Double.init)
    }

    static func number(_ word: String) -> Double? {
        Double(word) ?? NumberFormatter.spellOutNumber(word).map(Double.init)
    }

    static func fraction(_ word: String) -> Double? {
        let parts = word.split(separator: "/")
        guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0 else { return nil }
        return top / bottom
    }

    /// The word(s) right before "timer" that aren't filler, numbers or units: "pasta timer" → "pasta".
    static func nameBeforeTimer(_ words: [String]) -> String? {
        guard let timerIndex = words.firstIndex(where: { $0 == "timer" || $0 == "timers" }) else { return nil }
        var nameWords: [String] = []
        var i = timerIndex - 1
        while i >= 0 {
            let word = words[i]
            let isNumber = Double(word) != nil || fraction(word) != nil || NumberFormatter.spellOutNumber(word) != nil
            if nameStopWords.contains(word) || units[word] != nil || isNumber { break }
            nameWords.insert(word, at: 0)
            i -= 1
        }
        return nameWords.isEmpty ? nil : nameWords.joined(separator: " ")
    }
}

extension NumberFormatter {
    /// The value of a spelled-out English number word ("ten"), or nil.
    static func spellOutNumber(_ word: String) -> Int? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter.number(from: word)?.intValue
    }
}
