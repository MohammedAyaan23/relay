import Extraction
import Foundation

/// The real implementation: CoreAudio, key events, AppleScript, `screencapture` and the Shortcuts bridge.
public final class MacSystemControls: SystemControlling {
    private let shortcuts: ShortcutsBridge
    private let runner: any CommandRunning

    public init(shortcuts: ShortcutsBridge = ShortcutsBridge(), runner: any CommandRunning = ProcessRunner()) {
        self.shortcuts = shortcuts
        self.runner = runner
    }

    static func brightnessInput(percent: Int) -> String {
        String(format: "%.2f", Double(min(100, max(0, percent))) / 100)
    }

    public func volume() async throws -> Int { try CoreAudioVolume.volume() }
    public func setVolume(_ percent: Int) async throws { try CoreAudioVolume.setVolume(percent) }
    public func setMuted(_ muted: Bool) async throws { try CoreAudioVolume.setMuted(muted) }

    public func setBrightness(percent: Int) async throws {
        try await shortcuts.run(ShortcutsBridge.brightness, input: Self.brightnessInput(percent: percent))
    }

    public func stepBrightness(up: Bool, presses: Int) async throws {
        try Permissions.requireAccessibility()
        let code = up ? KeyEvents.brightnessUp : KeyEvents.brightnessDown
        await MainActor.run {
            for _ in 0..<presses { KeyEvents.pressSystemKey(code) }
        }
    }

    public func setFocus(on: Bool) async throws {
        try await shortcuts.run(on ? ShortcutsBridge.focusOn : ShortcutsBridge.focusOff)
    }

    public func setDarkMode(_ mode: SwitchCommand) async throws {
        try await MainActor.run { try AppearanceScript.run(mode) }
    }

    public func lockScreen() async throws {
        try Permissions.requireAccessibility()
        await MainActor.run { KeyEvents.pressLockShortcut() }
    }

    public func pressMediaKey(_ key: MediaKey) async throws {
        try Permissions.requireAccessibility()
        await MainActor.run { KeyEvents.pressSystemKey(KeyEvents.code(for: key)) }
    }

    public func takeScreenshot() async throws -> URL {
        try Permissions.requireScreenRecording()
        let folder = ScreenshotLocation.folder(
            defaultsValue: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser)
        let file = folder.appendingPathComponent(ScreenshotLocation.fileName(for: Date()))
        let result = try await runner.run("/usr/sbin/screencapture", ["-x", file.path])
        guard result.status == 0, FileManager.default.fileExists(atPath: file.path) else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "screencapture exited \(result.status)" : reason)
        }
        return file
    }
}
