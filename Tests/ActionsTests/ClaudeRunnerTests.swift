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
        "-p", "hi", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
    ])
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
    #expect(Array(args.suffix(2)) == ["--resume", session])
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
