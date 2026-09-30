import Foundation

/// One routed command, written to decisions.jsonl. This log is what grows the routing test set.
public struct DecisionLogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var transcript: String
    public var gateProbability: Float
    public var choiceProbabilities: [String: Float]
    /// "open_app", "web_search", "ask_claude", "new_claude_session", "not_a_command" or "ambiguous".
    public var outcome: String
    public var extracted: String?
    public var stateWasTruncated: Bool
    /// The message shown to the user.
    public var result: String

    public init(timestamp: Date, transcript: String, gateProbability: Float, choiceProbabilities: [String: Float],
                outcome: String, extracted: String?, stateWasTruncated: Bool, result: String) {
        self.timestamp = timestamp
        self.transcript = transcript
        self.gateProbability = gateProbability
        self.choiceProbabilities = choiceProbabilities
        self.outcome = outcome
        self.extracted = extracted
        self.stateWasTruncated = stateWasTruncated
        self.result = result
    }
}

public protocol DecisionLogging: Sendable {
    func append(_ entry: DecisionLogEntry)
}

/// Appends entries as JSON lines, keeping only the newest `maxEntries`, in a file only the user can read.
/// Write failures are ignored: logging must never break a command.
public struct DecisionLog: DecisionLogging {
    public static let maxEntries = 500
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relay/decisions.jsonl")
    }

    public func append(_ entry: DecisionLogEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        let fileManager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        var contents = (try? Data(contentsOf: fileURL)) ?? Data()
        contents.append(line)
        let lines = contents.split(separator: 0x0A, omittingEmptySubsequences: true)
        if lines.count > Self.maxEntries {
            contents = Data(lines.suffix(Self.maxEntries).joined(separator: [0x0A])) + [0x0A]
        }
        try? contents.write(to: fileURL, options: .atomic)
        // Also tightens a log written by an older Relay with default (world-readable) permissions.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Deletes the history (Settings → Clear command history).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
