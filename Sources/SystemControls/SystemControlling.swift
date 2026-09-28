import Extraction
import Foundation

public enum MediaKey: Sendable, Equatable {
    case playPause
    case next
    case previous
}

public enum SystemControlError: Error, Equatable {
    case noVolumeControl
    case shortcutMissing(String)
    case shortcutFailed(String, reason: String)
    /// The user hasn't allowed Relay to control this app (AppleScript error -1743).
    case automationDenied(String)
    case remindersDenied
    case accessibilityDenied
    case screenRecordingDenied
    case failed(String)
    case appNotRunning(String)
    case noFrontWindow
    case searchFailed(String)
}

/// Everything Relay can change on the Mac. A protocol so the assistant can be tested with a fake.
public protocol SystemControlling: Sendable {
    /// Current output volume, 0…100.
    func volume() async throws -> Int
    func setVolume(_ percent: Int) async throws
    func setMuted(_ muted: Bool) async throws
    /// Sets an exact brightness through the "Relay Brightness" shortcut.
    func setBrightness(percent: Int) async throws
    /// Presses the brightness keys; each press is about 1/16.
    func stepBrightness(up: Bool, presses: Int) async throws
    /// Turns Do Not Disturb on or off through the "Relay Focus On/Off" shortcuts.
    func setFocus(on: Bool) async throws
    func setDarkMode(_ mode: SwitchCommand) async throws
    /// Changes the keyboard backlight; returns the resulting percentage when it's known.
    func adjustKeyboardLight(_ command: LevelCommand) async throws -> Int?
    func lockScreen() async throws
    func pressMediaKey(_ key: MediaKey) async throws
}
