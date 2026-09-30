import Foundation
import Testing
@testable import Actions
@testable import AssistantCore
@testable import Routing

@MainActor @Test func prepareReachesIdle() async {
    let h = Harness()
    await h.assistant.prepare()
    #expect(h.assistant.phase == .idle)
    #expect(h.assistant.message == "Ready.")
}

@MainActor @Test func missingClaudeIsMentionedWhenReady() async {
    let h = Harness(withClaude: false)
    await h.assistant.prepare()
    #expect(h.assistant.message == "Ready. (Claude Code wasn't found. Set its path in Settings.)")
}

@MainActor @Test func micPermissionDeniedStaysPreparing() async {
    let h = Harness()
    h.recorder.permission = false
    await h.assistant.prepare()
    #expect(h.assistant.phase == .preparing)
    #expect(h.assistant.missingPermission == .microphone)
}

@MainActor @Test func speechPermissionDeniedStaysPreparing() async {
    let h = Harness()
    await h.transcriber.setPrepareError(.permissionDenied)
    await h.assistant.prepare()
    #expect(h.assistant.missingPermission == .speechRecognition)
}

@MainActor @Test func hotkeyIsIgnoredWhilePreparing() async {
    let h = Harness()
    await h.assistant.hotkeyPressed()
    #expect(h.recorder.starts == 0)
}

@MainActor @Test func fullCycleOpensTheAppAndLogsTheDecision() async {
    let h = Harness(transcript: "Open Safari.")
    await h.assistant.prepare()
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.phase == .listening)
    await h.assistant.hotkeyPressed()
    #expect(h.opener.opened == [safari.url])
    #expect(h.assistant.message == "Opened Safari.")
    #expect(h.assistant.phase == .idle)
    #expect(h.log.all.first?.outcome == "open_app")
    #expect(h.log.all.first?.extracted == "Safari")
}

@MainActor @Test func emptyTranscriptSkipsRouting() async {
    let h = Harness(transcript: "   ")
    await h.speak()
    #expect(h.assistant.message == "Didn't catch anything.")
    #expect(await h.router.routeCount == 0)
}

@MainActor @Test func nonCommandDoesNothing() async {
    let h = Harness(transcript: "i had a great lunch today", outcome: .notACommand)
    await h.speak()
    #expect(h.assistant.message == "Didn't sound like a command: “i had a great lunch today”")
    #expect(h.opener.opened.isEmpty)
}

@MainActor @Test func ambiguousShowsTopTwoAndDoesNothing() async {
    let h = Harness(outcome: .ambiguous([.openApp, .webSearch]))
    await h.speak()
    #expect(h.assistant.message == "Not sure what you meant. Maybe open an app or search the web?")
    #expect(h.opener.opened.isEmpty)
}

@MainActor @Test func unknownAppSuggestsClosest() async {
    let h = Harness(transcript: "open photoshop")
    await h.speak()
    #expect(h.assistant.message == "No app matching “photoshop”. Closest: Safari.")
}

@MainActor @Test func searchKeepsSymbols() async {
    let h = Harness(transcript: "google c++ tutorials", outcome: .intent(.webSearch))
    await h.speak()
    #expect(h.opener.opened == [WebSearch.url(for: "c++ tutorials")])
    #expect(h.assistant.message == "Searching the web for “c++ tutorials”.")
}

@MainActor @Test func emptySearchAsksWhatToSearch() async {
    let h = Harness(transcript: "search", outcome: .intent(.webSearch))
    await h.speak()
    #expect(h.assistant.message == "What should I search for?")
}

@MainActor @Test func claudeNeedsAnActiveProject() async {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude))
    h.assistant.activeProject = nil
    await h.speak()
    #expect(h.assistant.message == "No active project. Pick one from the menu.")
    #expect(await h.claude!.prompts.isEmpty)
}

@MainActor @Test func claudeMissingIsExplained() async {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude), withClaude: false)
    await h.speak()
    #expect(h.assistant.message == "Couldn't find the claude command. Set its path in Settings, then restart Relay.")
}

@MainActor @Test func deletedProjectFolderIsExplained() async throws {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude))
    try FileManager.default.removeItem(at: h.project)
    await h.speak()
    #expect(h.assistant.message == "The active project folder no longer exists: \(h.project.path). Pick another from the menu.")
    #expect(await h.claude!.prompts.isEmpty)
}

@MainActor @Test func claudeJobStreamsAndReportsBlockedTools() async {
    let h = Harness(transcript: "Ask Claude to add tests for the parser.", outcome: .intent(.askClaude))
    let result = ClaudeResult(text: "Added 4 tests.", sessionID: "s1", durationMs: 12_000, costUSD: 0.05,
                              isError: false, deniedTools: ["Bash: swift test"])
    await h.claude!.setScript([.sessionStarted(sessionID: "s1"), .text("Working"), .finished(result)])
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(await h.claude!.prompts == ["add tests for the parser"])
    #expect(h.assistant.claudeRunning == false)
    #expect(h.assistant.claudeEvents.contains(.text("Working")))
    #expect(h.assistant.message == "Claude finished in 12s ($0.05). Blocked: Bash: swift test.")
    #expect(h.notifications == ["Claude finished"])
}

@MainActor @Test func claudeFailureIsReportedOnce() async {
    let h = Harness(transcript: "ask claude to continue", outcome: .intent(.askClaude))
    let errorResult = ClaudeResult(text: nil, sessionID: "x", durationMs: 0, costUSD: 0, isError: true, deniedTools: [])
    await h.claude!.setScript([.finished(errorResult), .failed(exitCode: 1, stderrTail: "No conversation found")])
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(h.assistant.message == "Claude failed (exit 1): No conversation found")
    #expect(h.notifications == ["Claude failed"])
}

@MainActor @Test func busyClaudeRefusesAnotherJob() async {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude))
    await h.claude!.setRunning(true)
    await h.speak()
    #expect(h.assistant.message == "Claude is still working. Stop it first.")
    #expect(await h.claude!.prompts.isEmpty)
}

@MainActor @Test func hotkeyStartsNewRecordingWhileClaudeRuns() async {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude))
    await h.claude!.setHoldOpen(true)
    await h.speak()
    #expect(h.assistant.claudeRunning)
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.phase == .listening)
    #expect(h.recorder.starts == 2)
    await h.claude!.release()
    await h.assistant.waitForClaudeJob()
    #expect(h.assistant.claudeRunning == false)
}

@MainActor @Test func longDictationReachesClaudeInFull() async {
    let body = Array(repeating: "refactor the parser module", count: 60).joined(separator: " and ")
    let h = Harness(transcript: "ask claude to " + body, outcome: .intent(.askClaude))
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(await h.claude!.prompts == [body])
}

@MainActor @Test func newSessionClearsTheProjectsSession() async {
    let h = Harness(transcript: "start a new claude session", outcome: .intent(.newClaudeSession))
    await h.speak()
    #expect(await h.claude!.cleared == [h.project])
    #expect(h.assistant.message == "Started a new Claude session for \(h.project.lastPathComponent).")
}

@MainActor @Test func stoppedJobSaysSo() async {
    let h = Harness(transcript: "ask claude to add tests", outcome: .intent(.askClaude))
    await h.claude!.setScript([.stopped])
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(h.assistant.message == "Stopped Claude.")
    #expect(h.notifications.isEmpty)
}

// MARK: Final-review findings

@MainActor @Test func claudeErrorWithEmptyStderrShowsTheResultText() async {
    let h = Harness(transcript: "ask claude to continue", outcome: .intent(.askClaude))
    let errorResult = ClaudeResult(text: "Invalid API key · Please run /login", sessionID: "x", durationMs: 0,
                                   costUSD: 0, isError: true, deniedTools: [])
    await h.claude!.setScript([.finished(errorResult), .failed(exitCode: 1, stderrTail: "")])
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(h.assistant.message == "Claude failed (exit 1): Invalid API key · Please run /login")
    #expect(h.notifications == ["Claude failed"])
}

@MainActor @Test func claudeErrorThatExitsCleanlyStillNotifies() async {
    let h = Harness(transcript: "ask claude to continue", outcome: .intent(.askClaude))
    let errorResult = ClaudeResult(text: "Credit balance is too low", sessionID: "x", durationMs: 0,
                                   costUSD: 0, isError: true, deniedTools: [])
    await h.claude!.setScript([.finished(errorResult)])
    await h.speak()
    await h.assistant.waitForClaudeJob()
    #expect(h.assistant.message == "Claude reported an error: Credit balance is too low")
    #expect(h.notifications == ["Claude failed"])
}

@MainActor @Test func failedSetupCanBeRetried() async {
    let h = Harness()
    await h.transcriber.setPrepareError(.localeUnsupported)
    await h.assistant.prepare()
    #expect(h.assistant.phase == .preparing)
    #expect(h.assistant.prepareFailed)
    await h.transcriber.setPrepareError(nil)
    await h.assistant.prepare()
    #expect(h.assistant.phase == .idle)
    #expect(!h.assistant.prepareFailed)
}

// MARK: Listening HUD

@MainActor @Test func inputLevelIsTheMicLevelOnlyWhileListening() async {
    let h = Harness()
    await h.assistant.prepare()
    #expect(h.assistant.inputLevel == 0)
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.inputLevel == 0.6)
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.inputLevel == 0)
}

@MainActor @Test func successfulCommandIsMarkedSuccess() async {
    let h = Harness(transcript: "open safari")
    await h.speak()
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func nonCommandIsMarkedInfo() async {
    let h = Harness(transcript: "i had a great lunch today", outcome: .notACommand)
    await h.speak()
    #expect(h.assistant.resultKind == .info)
}

@MainActor @Test func unknownAppIsMarkedProblem() async {
    let h = Harness(transcript: "open photoshop")
    await h.speak()
    #expect(h.assistant.resultKind == .problem)
}

@MainActor @Test func startingToListenClearsThePreviousResultKind() async {
    let h = Harness(transcript: "open safari")
    await h.speak()
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.resultKind == nil)
}

// The log keeps command phrases (they grow the routing tests) but not what you dictated or said in passing.
@MainActor @Test func privateSpeechIsNotLogged() async {
    let cases: [(String, RoutingDecision.Outcome)] = [
        ("i had a great lunch today", .notACommand),
        ("type my password is hunter2", .intent(.typeText)),
        ("note that the doctor called", .intent(.addNote)),
        ("remind me to call the clinic at 5pm", .intent(.addReminder)),
    ]
    for (transcript, outcome) in cases {
        let h = Harness(transcript: transcript, outcome: outcome)
        await h.speak()
        let entry = h.log.all.first
        #expect(entry?.transcript == "", "\(transcript)")
        #expect(entry?.extracted == nil, "\(transcript)")
        #expect(entry?.result == "", "\(transcript)")
        #expect(entry?.outcome == outcome.logName)
    }
}
