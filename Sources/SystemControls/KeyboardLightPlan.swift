import Extraction

/// The maths for keyboard-light commands, shared by the precise route and the key-press fallback.
public enum KeyboardLightPlan {
    /// The illumination keys move the backlight in 16 steps of 6.25%.
    static let steps = 16

    public struct Presses: Equatable, Sendable {
        public let down: Int
        public let up: Int
    }

    /// The level (0…1) a command asks for, given the current level. "off" arrives as `.mute`, "on" as `.unmute`.
    public static func target(for command: LevelCommand, current: Double) -> Double {
        switch command {
        case .set(let percent): Double(percent) / 100
        case .up(let step): min(1, current + Double(step) / 100)
        case .down(let step): max(0, current - Double(step) / 100)
        case .mute: 0
        case .unmute: 0.5
        }
    }

    /// Key presses for the fallback. With no way to read the level publicly, absolute levels count up from zero.
    public static func presses(for command: LevelCommand) -> Presses {
        switch command {
        case .set(let percent): Presses(down: steps, up: stepsFor(percent))
        case .mute: Presses(down: steps, up: 0)
        case .unmute: Presses(down: steps, up: stepsFor(50))
        case .up(let step): Presses(down: 0, up: step <= 6 ? 1 : 2)
        case .down(let step): Presses(down: step <= 6 ? 1 : 2, up: 0)
        }
    }

    /// The level the fallback reaches, when it's knowable (absolute commands only).
    public static func resultingPercent(for command: LevelCommand) -> Int? {
        switch command {
        case .set(let percent): Int((Double(stepsFor(percent)) * 100 / Double(steps)).rounded())
        case .mute: 0
        case .unmute: 50
        case .up, .down: nil
        }
    }

    static func stepsFor(_ percent: Int) -> Int {
        Int((Double(min(100, max(0, percent))) * Double(steps) / 100).rounded())
    }
}
