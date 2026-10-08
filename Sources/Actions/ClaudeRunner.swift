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
    /// The running claude process's ID (for tests).
    var processID: Int32? { process?.processIdentifier }

    public func arguments(prompt: String, project: URL) -> [String] {
        // Claude may read and edit files in the project, but gets no shell: acceptEdits also auto-approves
        // commands like rm and mv. The project's own settings, hooks and MCP servers are ignored, since -p
        // skips Claude Code's "trust this folder" prompt.
        var arguments = ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
                         "--tools", "Read,Grep,Glob,Edit,Write", "--setting-sources", "user", "--strict-mcp-config"]
        if let id = sessions.sessionID(for: project) { arguments += ["--resume", id] }
        // After "--", a prompt starting with "-" can't be read as an option.
        return arguments + ["--", prompt]
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
        let output = PipeReader(stdout.fileHandleForReading)
        let errors = PipeReader(stderr.fileHandleForReading)
        let exit = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exit.continuation.yield(finished.terminationStatus)
            exit.continuation.finish()
            // The pipes normally close as Claude exits. A leftover child process can hold them open, which
            // used to keep the runner busy for as long as the child lived; stop listening shortly after exit.
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                output.finish()
                errors.finish()
            }
        }
        try process.run()
        self.process = process
        stopRequested = false

        let (events, continuation) = AsyncStream<ClaudeEvent>.makeStream()
        let sessions = sessions
        Task {
            for await line in output.lines {
                for event in ClaudeStreamParser.parse(line: line) {
                    if case .finished(let result) = event, !result.isError, !result.sessionID.isEmpty {
                        try? sessions.setSessionID(result.sessionID, for: project)
                    }
                    continuation.yield(event)
                }
            }
            var status: Int32 = 0
            for await code in exit.stream { status = code }
            for await _ in errors.lines {} // until stderr ends (or the grace period stops it)
            let errorText = errors.text
            if errorText.contains("No conversation found") {
                try? sessions.setSessionID(nil, for: project)
            }
            if stopRequested {
                continuation.yield(.stopped)
            } else if status != 0 {
                continuation.yield(.failed(exitCode: status, stderrTail: Self.tail(errorText, lines: 20)))
            }
            self.process = nil
            continuation.finish()
        }
        return events
    }

    /// Interrupts the running job (like Ctrl-C), then terminates it if it's still alive after 3 seconds.
    public func stop() async {
        await stop(grace: .seconds(3))
    }

    /// Returns only once claude has exited (or after a final 2 s), so quitting Relay can't leave it running:
    /// a Task scheduled to terminate it later would die with Relay.
    func stop(grace: Duration) async {
        guard let process, process.isRunning else { return }
        stopRequested = true
        process.interrupt()
        if await Self.waitForExit(process, upTo: grace) { return }
        process.terminate()
        _ = await Self.waitForExit(process, upTo: .seconds(2))
    }

    private static func waitForExit(_ process: Process, upTo limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !process.isRunning
    }

    static func tail(_ text: String, lines: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(lines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
