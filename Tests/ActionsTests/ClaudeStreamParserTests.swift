import Testing
@testable import Actions

private let session = "11111111-1111-1111-1111-111111111111"

@Test func parsesARealSuccessfulRunInOrder() throws {
    let events = try Fixtures.lines("stream-success.jsonl").flatMap(ClaudeStreamParser.parse(line:))
    #expect(events == [
        .ignored(type: "system/hook_started"),
        .sessionStarted(sessionID: session),
        .ignored(type: "system/thinking_tokens"),
        .toolUse(name: "Read", summary: "note.txt"),
        .ignored(type: "rate_limit_event"),
        .toolResult(isError: false),
        .text("hello from relay"),
        .finished(ClaudeResult(text: "hello from relay", sessionID: session, durationMs: 6151,
                               costUSD: 0.0286, isError: false, deniedTools: [])),
    ])
}

@Test func reportsToolCallsClaudeWasNotAllowedToMake() throws {
    let events = try Fixtures.lines("stream-denied.jsonl").flatMap(ClaudeStreamParser.parse(line:))
    #expect(events.contains(.toolUse(name: "Bash", summary: "python3 -c 'print(40+2)'")))
    #expect(events.contains(.toolResult(isError: true)))
    guard case .finished(let result) = events.last else { Issue.record("no result"); return }
    #expect(result.deniedTools == ["Bash: python3 -c 'print(40+2)'"])
}

@Test func parsesAnErrorResult() throws {
    let events = try Fixtures.lines("stream-bad-resume.jsonl").flatMap(ClaudeStreamParser.parse(line:))
    guard case .finished(let result) = events.first else { Issue.record("no result"); return }
    #expect(result.isError)
    #expect(result.costUSD == 0)
}

@Test func invalidAndUnknownLinesAreIgnoredNotFatal() {
    #expect(ClaudeStreamParser.parse(line: "not json {") == [.ignored(type: "invalid-json")])
    #expect(ClaudeStreamParser.parse(line: #"{"type":"mystery"}"#) == [.ignored(type: "mystery")])
    #expect(ClaudeStreamParser.parse(line: "   ") == [])
}
