public struct ScreenshotOptions: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case screen, window, area
    }

    public var target: Target
    public var toClipboard: Bool
    public var openAfter: Bool

    public init(target: Target, toClipboard: Bool, openAfter: Bool) {
        self.target = target
        self.toClipboard = toClipboard
        self.openAfter = openAfter
    }
}

/// Reads screenshot variants: "screenshot this window", "copy a screenshot", "…and show it".
public enum ScreenshotOptionsParser {
    public static func parse(_ transcript: String) -> ScreenshotOptions {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        func has(_ phrases: [String]) -> Bool { phrases.contains { padded.contains(" \($0) ") } }
        let target: ScreenshotOptions.Target =
            has(["area", "region", "part of the screen", "select", "selection"]) ? .area
            : has(["window"]) ? .window
            : .screen
        let toClipboard = has(["copy", "clipboard"])
        let openAfter = !toClipboard && has(["show it", "open it", "show me"])
        return ScreenshotOptions(target: target, toClipboard: toClipboard, openAfter: openAfter)
    }
}
