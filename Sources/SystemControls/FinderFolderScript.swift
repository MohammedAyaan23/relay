import Foundation

/// Asks Finder for the folder of its front window, through `/usr/bin/osascript`.
public enum FinderFolderScript {
    static let source = "tell application \"Finder\" to if (count of Finder windows) > 0 then "
        + "POSIX path of (target of front Finder window as alias)"

    /// The folder path from osascript's output; nil when there's no Finder window or Finder errored.
    /// Error -1743 means the user hasn't allowed Relay to control Finder.
    public static func interpret(_ result: CommandResult) throws -> URL? {
        guard result.status == 0 else {
            if result.stderr.contains("-1743") { throw SystemControlError.automationDenied }
            return nil
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "missing value" else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
