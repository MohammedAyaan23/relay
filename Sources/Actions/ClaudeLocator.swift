import Foundation

/// Finds the `claude` executable. Apps launched from Finder or the menu bar don't inherit the
/// shell's PATH, so ask the login shell instead.
public enum ClaudeLocator {
    public static func locate(override: String?, shellLookup: () -> String? = loginShellLookup) -> URL? {
        let fileManager = FileManager.default
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let path = (override.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        guard let found = shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !found.isEmpty, fileManager.isExecutableFile(atPath: found)
        else { return nil }
        return URL(fileURLWithPath: found)
    }

    public static func loginShellLookup() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        // Login shells can print banners; the path is the last line.
        return String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init)
    }
}
