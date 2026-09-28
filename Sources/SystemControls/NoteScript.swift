import Foundation

/// The two AppleScripts for the "Relay" note. Text only ever travels as an `osascript` argument.
public enum NoteScript {
    static let readLines = [
        "on run argv",
        "tell application \"Notes\"",
        "set found to notes whose name is \"Relay\"",
        "if (count of found) is 0 then return \"\"",
        "return body of item 1 of found",
        "end tell",
        "end run",
    ]
    static let writeLines = [
        "on run argv",
        "set newBody to item 1 of argv",
        "tell application \"Notes\"",
        "set found to notes whose name is \"Relay\"",
        "if (count of found) is 0 then",
        "make new note with properties {body:newBody}",
        "else",
        "set body of item 1 of found to newBody",
        "end if",
        "end tell",
        "end run",
    ]

    public static func readArguments() -> [String] {
        readLines.flatMap { ["-e", $0] }
    }

    public static func writeArguments(body: String) -> [String] {
        writeLines.flatMap { ["-e", $0] } + [body]
    }

    /// The note body on success; -1743 means Relay isn't allowed to control Notes.
    public static func interpret(_ result: CommandResult) throws -> String {
        guard result.status == 0 else {
            if result.stderr.contains("-1743") { throw SystemControlError.automationDenied("Notes") }
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "osascript exited \(result.status)" : reason)
        }
        return result.stdout.trimmingCharacters(in: .newlines)
    }
}
