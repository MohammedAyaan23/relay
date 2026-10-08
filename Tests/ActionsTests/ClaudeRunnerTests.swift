import Foundation
import Testing
@testable import Actions

private let session = "11111111-1111-1111-1111-111111111111"

private struct Setup {
    let project: URL
    let store: SessionStore
    let runner: ClaudeRunner

    init() throws {
        project = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        store = SessionStore(fileURL: project.appendingPathComponent("sessions.json"))
        runner = ClaudeRunner(executable: Fixtures.url("fake-claude.sh"), sessions: store)
    }

    func recordedArguments() throws -> [String] {
        try String(contentsOf: project.appendingPathComponent("args.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }
}

private func collect(_ stream: AsyncStream<ClaudeEvent>) async -> [ClaudeEvent] {
    var events: [ClaudeEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@Test func firstRunHasNoResumeFlag() async throws {
    let s = try Setup()
    #expect(await s.runner.arguments(prompt: "hi", project: s.project) == [
        "-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
        "--tools", "Read,Grep,Glob,Edit,Write", "--setting-sources", "user", "--strict-mcp-config", "--", "hi",
    ])
}

// Claude may read and edit files in the project, but gets no shell (acceptEdits would auto-approve rm/mv),
// and the project's own settings, hooks and MCP servers are ignored.
@Test func claudeGetsNoShellAndIgnoresProjectSettings() async throws {
    let s = try Setup()
    let args = await s.runner.arguments(prompt: "hi", project: s.project)
    let tools = args[args.firstIndex(of: "--tools")! + 1]
    #expect(!tools.contains("Bash"))
    #expect(args[args.firstIndex(of: "--setting-sources")! + 1] == "user")
    #expect(args.contains("--strict-mcp-config"))
}

// A prompt that starts with "-" must stay the prompt, not become an option.
@Test func promptComesAfterDoubleDash() async throws {
    let s = try Setup()
    let args = await s.runner.arguments(prompt: "--dangerously-skip-permissions", project: s.project)
    #expect(Array(args.suffix(2)) == ["--", "--dangerously-skip-permissions"])
}

@Test func successfulRunStoresTheSessionAndTheNextRunResumesIt() async throws {
    let s = try Setup()
    let events = await collect(try await s.runner.run(prompt: "ok", project: s.project))
    #expect(events.contains(.sessionStarted(sessionID: session)))
    #expect(events.contains(.text("hello from relay")))
    #expect(s.store.sessionID(for: s.project) == session)
    #expect(await s.runner.isRunning == false)

    _ = await collect(try await s.runner.run(prompt: "ok", project: s.project))
    let args = try s.recordedArguments()
    #expect(args.firstIndex(of: "--resume").map { args[$0 + 1] } == session)
}

@Test func secondJobWhileRunningIsRefusedAndStopEndsTheFirst() async throws {
    let s = try Setup()
    let stream = try await s.runner.run(prompt: "slow", project: s.project)
    #expect(await s.runner.isRunning)
    await #expect(throws: ClaudeRunnerError.busy) {
        _ = try await s.runner.run(prompt: "ok", project: s.project)
    }
    await s.runner.stop()
    let events = await collect(stream)
    #expect(events.last == .stopped)
    #expect(await s.runner.isRunning == false)
}

@Test func unknownSessionIsReportedAndForgotten() async throws {
    let s = try Setup()
    try s.store.setSessionID("stale-session", for: s.project)
    let events = await collect(try await s.runner.run(prompt: "bad-resume", project: s.project))
    guard case .failed(let code, let tail) = events.last else { Issue.record("expected failure"); return }
    #expect(code == 1)
    #expect(tail.contains("No conversation found"))
    #expect(s.store.sessionID(for: s.project) == nil)
}

@Test func processEndingWithoutAResultIsAFailureAndFreesTheRunner() async throws {
    let s = try Setup()
    let events = await collect(try await s.runner.run(prompt: "crash", project: s.project))
    #expect(events.last == .failed(exitCode: 2, stderrTail: "segfault-ish failure"))
    #expect(s.store.sessionID(for: s.project) == nil)
    #expect(await s.runner.isRunning == false)
}

@Test func clearSessionForgetsTheProjectsSession() async throws {
    let s = try Setup()
    try s.store.setSessionID("abc", for: s.project)
    try await s.runner.clearSession(for: s.project)
    #expect(s.store.sessionID(for: s.project) == nil)
}

/// A child process that keeps Claude's output pipe open (here: the fake's background `sleep 30`) must not
/// keep the runner busy after Stop. Waiting first lets the fake install its handler and start the child.
@Test func stopFinishesPromptlyEvenIfAChildHoldsTheOutputOpen() async throws {
    let s = try Setup()
    let stream = try await s.runner.run(prompt: "slow", project: s.project)
    try await Task.sleep(for: .milliseconds(500))
    let start = ContinuousClock.now
    await s.runner.stop()
    let events = await collect(stream)
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(events.last == .stopped)
    #expect(await s.runner.isRunning == false)
}

// Quitting Relay must not leave Claude running: stop() waits for it to exit, terminating it if it ignores Ctrl-C.
@Test func stopWaitsUntilAStubbornJobHasExited() async throws {
    let s = try Setup()
    let stream = try await s.runner.run(prompt: "stubborn", project: s.project)
    let pid = try #require(await s.runner.processID)
    try await Task.sleep(for: .milliseconds(200)) // let it install its signal traps
    await s.runner.stop(grace: .milliseconds(300))
    #expect(kill(pid, 0) != 0) // gone by the time stop() returns
    let events = await collect(stream)
    #expect(events.last == .stopped)
}
