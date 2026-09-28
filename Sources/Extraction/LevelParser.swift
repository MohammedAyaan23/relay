import Foundation

public enum LevelCommand: Equatable, Sendable {
    case set(Int)
    case up(Int)
    case down(Int)
    case mute
    case unmute
}

/// Reads a volume or brightness request: "40 percent", "forty five", "half", "a bit louder", "mute".
public enum LevelParser {
    static let upWords = ["up", "louder", "brighter", "raise", "increase", "crank", "turn up", "too dark", "too quiet"]
    static let downWords = ["down", "quieter", "dimmer", "dim", "lower", "decrease", "reduce", "turn down",
                            "too loud", "too bright"]
    static let smallStepWords = ["a bit", "a little", "slightly"]
    static let maxWords = ["max", "maximum", "all the way up", "full"]
    static let minWords = ["min", "minimum", "all the way down"]

    public static func parse(_ transcript: String) -> LevelCommand? {
        let text = TextNormalizer.normalize(transcript)
        let padded = " \(text) "
        func has(_ phrases: [String]) -> Bool { phrases.contains { padded.contains(" \($0) ") } }

        if has(["unmute"]) { return .unmute }
        if has(["mute", "silence the sound"]) { return .mute }
        if let number = number(in: text) { return .set(min(100, max(0, number))) }
        if has(["half"]) { return .set(50) }
        if has(maxWords) { return .set(100) }
        if has(minWords) { return .set(0) }
        let step = has(smallStepWords) ? 6 : 10
        if has(downWords) { return .down(step) }
        if has(upWords) { return .up(step) }
        return nil
    }

    /// The first number in the text: digits ("40") or spelled out ("forty five", "one hundred").
    static func number(in text: String) -> Int? {
        let words = text.split(separator: " ").map(String.init)
        if let digits = words.first(where: { Int($0) != nil }) { return Int(digits) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let run = words[start..<start + length]
                // Hyphenated first: the formatter reads "forty five" as 4005 but "forty-five" as 45,
                // while "one hundred" only parses with a space.
                for candidate in [run.joined(separator: "-"), run.joined(separator: " ")] {
                    if let value = formatter.number(from: candidate)?.intValue, value >= 0 { return value }
                }
            }
        }
        return nil
    }
}
