import Foundation

/// The two AppleScripts for the "Relay" note. Text only ever travels as an `osascript` argument.
public enum NoteScript {
    static let readLines = [
        "on run argv",
        "set out to \"\"",
        "tell application \"Notes\"",
        "repeat with n in (notes whose name is \"Relay\")",
        "if name of container of n is not \"Recently Deleted\" then",
        "set out to out & (id of n) & (character id 31) & (count of attachments of n) & (character id 31) & (body of n) & (character id 30)",
        "end if",
        "end repeat",
        "end tell",
        "return out",
        "end run",
    ]
    static let writeLines = [
        "on run argv",
        "set newBody to item 1 of argv",
        "set noteID to item 2 of argv",
        "tell application \"Notes\"",
        "if noteID is \"\" then",
        "set n to make new note with properties {body:newBody}",
        "else",
        "set n to note id noteID",
        "set body of n to newBody",
        "end if",
        "return id of n",
        "end tell",
        "end run",
    ]

    /// Lists every note titled "Relay" outside Recently Deleted: id, attachment count and body.
    public static func readArguments() -> [String] {
        readLines.flatMap { ["-e", $0] }
    }

    /// Saves `body` into the note with `noteID`, or creates a new note when `noteID` is nil.
    public static func writeArguments(body: String, noteID: String?) -> [String] {
        writeLines.flatMap { ["-e", $0] } + [body, noteID ?? ""]
    }

    /// Parses `readArguments` output: records separated by U+001E, fields by U+001F.
    public static func candidates(from output: String) -> [NoteCandidate] {
        output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            return NoteCandidate(id: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                                 attachments: Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                                 body: String(fields[2]))
        }
    }

    /// Relay's own note (the one carrying `NoteBody.marker`), or nil to create one. A note with attachments
    /// is never rewritten, because rewriting the body would drop them.
    public static func relayNote(in candidates: [NoteCandidate]) throws -> NoteCandidate? {
        guard let note = candidates.first(where: { $0.body.contains(NoteBody.marker) }) else { return nil }
        guard note.attachments == 0 else {
            throw SystemControlError.failed("the Relay note has attachments, so Relay won't rewrite it")
        }
        return note
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
