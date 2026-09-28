import Foundation

/// Runs Relay's helper shortcuts with `/usr/bin/shortcuts`. macOS has no public API for brightness or
/// Focus; the Shortcuts app's own "Set Brightness"/"Set Focus" actions are the supported route.
public actor ShortcutsBridge {
    public static let brightness = "Relay Brightness"
    public static let focusOn = "Relay Focus On"
    public static let focusOff = "Relay Focus Off"

    private let runner: any CommandRunning
    private let temporaryDirectory: URL
    private var installed: Set<String> = []

    public init(runner: any CommandRunning = ProcessRunner(),
                temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.runner = runner
        self.temporaryDirectory = temporaryDirectory
    }

    /// Runs `name`, passing `input` through a temporary text file (the CLI only takes input files).
    public func run(_ name: String, input: String? = nil) async throws {
        try await ensureInstalled(name)
        var arguments = ["run", name]
        var inputFile: URL?
        if let input {
            let file = temporaryDirectory.appendingPathComponent("relay-shortcut-\(UUID().uuidString).txt")
            try input.write(to: file, atomically: true, encoding: .utf8)
            arguments += ["-i", file.path]
            inputFile = file
        }
        let result: CommandResult
        do {
            result = try await runner.run("/usr/bin/shortcuts", arguments)
        } catch {
            if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
            throw SystemControlError.shortcutFailed(name, reason: error.localizedDescription)
        }
        if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.shortcutFailed(name, reason: reason.isEmpty ? "exit \(result.status)" : reason)
        }
    }

    private func ensureInstalled(_ name: String) async throws {
        if installed.contains(name) { return }
        let list = try await runner.run("/usr/bin/shortcuts", ["list"])
        installed = Set(list.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        guard installed.contains(name) else { throw SystemControlError.shortcutMissing(name) }
    }
}
