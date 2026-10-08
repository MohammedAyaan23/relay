import Foundation

/// Finds the `claude` executable. Apps launched from Finder or the menu bar don't inherit the
/// shell's PATH, so check the standard install locations, then ask the login shell (with a time limit).
public enum ClaudeLocator {
    /// Where Claude Code's installers put it, checked before starting a shell.
    public static var standardLocations: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"]
    }

    public static func locate(override: String?, knownLocations: [String] = standardLocations,
                              shellLookup: () -> String? = loginShellLookup) -> URL? {
        let fileManager = FileManager.default
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let path = (override.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if let known = knownLocations.first(where: fileManager.isExecutableFile) {
            return URL(fileURLWithPath: known)
        }
        guard let found = shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !found.isEmpty, fileManager.isExecutableFile(atPath: found)
        else { return nil }
        return URL(fileURLWithPath: found)
    }

    public static func loginShellLookup() -> String? {
        run("/bin/zsh", ["-lc", "command -v claude"], timeout: .seconds(3))
    }

    /// Runs a lookup command and returns the last line it printed. Gives up after `timeout` (a startup file
    /// that hangs can't freeze Relay), and doesn't wait for a background process that keeps the output open.
    static func run(_ executable: String, _ arguments: [String], timeout: Duration) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let reader = PipeReader(output.fileHandleForReading)
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        guard exited.wait(timeout: .now() + seconds) == .success else {
            process.terminate()
            reader.finish()
            return nil
        }
        Thread.sleep(forTimeInterval: 0.05) // let the last output arrive
        reader.finish()
        guard process.terminationStatus == 0 else { return nil }
        // Login shells can print banners; the path is the last line.
        return reader.text.split(separator: "\n").last.map(String.init)
    }
}
