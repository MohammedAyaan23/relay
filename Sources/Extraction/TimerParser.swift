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
                                       "second": 1, "seconds": 1, "sec": 1, "secs": 1]
    static let nameStopWords: Set<String> = ["a", "an", "the", "my", "set", "start", "new", "for", "me", "timer",
                                             "cancel", "stop", "delete", "clear", "remove", "on", "left", "is",
                                             "how", "long", "much", "time", "all", "every", "of", "and", "half"]

    public static func parse(_ transcript: String) -> TimerRequest {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        var seconds = 0
        var found = false
        for (i, word) in words.enumerated() {
            guard let unit = units[word] else { continue }
            if i >= 2, words[i - 2] == "half", words[i - 1] == "an" || words[i - 1] == "a" {
                seconds += unit / 2
                found = true
            } else if let amount = amount(before: i, in: words) {
                seconds += amount * unit
                found = true
            }
            if i + 3 < words.count, words[i + 1] == "and", words[i + 2] == "a", words[i + 3] == "half" {
                seconds += unit / 2
            }
        }
        if !found, words.contains("pomodoro") {
            seconds = 1500
            found = true
        }
        var name = nameBeforeTimer(words)
        if name == nil, words.contains("pomodoro") { name = "pomodoro" }
        return TimerRequest(seconds: found ? seconds : nil, name: name)
    }

    public static func target(_ transcript: String) -> TimerTarget {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        if words.contains("all") || words.contains("every") { return .all }
        if let name = nameBeforeTimer(words) { return .named(name) }
        return .unspecified
    }

    /// Digits, "a"/"an", or a spelled number (hyphenated first: "forty five" parses as 4005 when spaced).
    static func amount(before index: Int, in words: [String]) -> Int? {
        guard index >= 1 else { return nil }
        let previous = words[index - 1]
        if let value = Int(previous) { return value }
        if previous == "a" || previous == "an" { return 1 }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        if index >= 2, let value = formatter.number(from: "\(words[index - 2])-\(previous)")?.intValue { return value }
        return formatter.number(from: previous)?.intValue
    }

    /// The word(s) right before "timer" that aren't filler, numbers or units: "pasta timer" → "pasta".
    static func nameBeforeTimer(_ words: [String]) -> String? {
        guard let timerIndex = words.firstIndex(where: { $0 == "timer" || $0 == "timers" }) else { return nil }
        var nameWords: [String] = []
        var i = timerIndex - 1
        while i >= 0 {
            let word = words[i]
            let isNumber = Int(word) != nil || NumberFormatter.spellOutNumber(word) != nil
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
