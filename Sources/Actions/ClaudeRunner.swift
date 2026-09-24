import Foundation

public enum ClaudeRunnerError: Error, Equatable {
    case busy
}

public protocol ClaudeJobRunning: Sendable {
    func run(prompt: String, project: URL) async throws -> AsyncStream<ClaudeEvent>
    func stop() async
    func clearSession(for project: URL) async throws
    var isRunning: Bool { get async }
}

/// Runs `claude -p` headlessly in a project folder, one job at a time, and streams its events.
public actor ClaudeRunner: ClaudeJobRunning {
    private let executable: URL
    private let sessions: SessionStore
    private var process: Process?
    private var stopRequested = false

    public init(executable: URL, sessions: SessionStore) {
        self.executable = executable
        self.sessions = sessions
    }

    public var isRunning: Bool { process != nil }

    public func arguments(prompt: String, project: URL) -> [String] {
        var arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits"]
        if let id = sessions.sessionID(for: project) { arguments += ["--resume", id] }
        return arguments
    }

    public func clearSession(for project: URL) throws {
        try sessions.setSessionID(nil, for: project)
    }

    public func run(prompt: String, project: URL) throws -> AsyncStream<ClaudeEvent> {
        guard process == nil else { throw ClaudeRunnerError.busy }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(prompt: prompt, project: project)
        process.currentDirectoryURL = project
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let exit = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exit.continuation.yield(finished.terminationStatus)
            exit.continuation.finish()
        }
        try process.run()
        self.process = process
        stopRequested = false

        let (events, continuation) = AsyncStream<ClaudeEvent>.makeStream()
        let sessions = sessions
        Task {
            let stderrText = Task { await Self.readAll(stderr.fileHandleForReading) }
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    for event in ClaudeStreamParser.parse(line: line) {
                        if case .finished(let result) = event, !result.isError, !result.sessionID.isEmpty {
                            try? sessions.setSessionID(result.sessionID, for: project)
                        }
                        continuation.yield(event)
                    }
                }
            } catch {
                continuation.yield(.ignored(type: "stdout-read-error"))
            }
            var status: Int32 = 0
            for await code in exit.stream { status = code }
            let errors = await stderrText.value
            if errors.contains("No conversation found") {
                try? sessions.setSessionID(nil, for: project)
            }
            if stopRequested {
                continuation.yield(.stopped)
            } else if status != 0 {
                continuation.yield(.failed(exitCode: status, stderrTail: Self.tail(errors, lines: 20)))
            }
            self.process = nil
            continuation.finish()
        }
        return events
    }

    /// Interrupts the running job (like Ctrl-C), then terminates it if it's still alive after 3 seconds.
    public func stop() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        process.interrupt()
        Task {
            try? await Task.sleep(for: .seconds(3))
            if process.isRunning { process.terminate() }
        }
    }

    private static func readAll(_ handle: FileHandle) async -> String {
        var data = Data()
        do {
            for try await byte in handle.bytes { data.append(byte) }
        } catch {}
        return String(decoding: data, as: UTF8.self)
    }

    static func tail(_ text: String, lines: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(lines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
