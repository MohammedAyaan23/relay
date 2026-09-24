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

/// Appends entries as JSON lines. Write failures are ignored: logging must never break a command.
public struct DecisionLog: DecisionLogging {
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
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: line)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
