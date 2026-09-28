import Foundation
import Synchronization
@testable import Actions
@testable import AssistantCore
@testable import Capture
@testable import Extraction
@testable import Routing
@testable import SystemControls
@testable import Transcription

@MainActor
final class FakeRecorder: AudioRecording {
    var permission = true
    var level: Float = 0.6
    var startError: Error?
    private(set) var starts = 0

    func requestPermission() async -> Bool { permission }
    func start() throws {
        if let startError { throw startError }
        starts += 1
    }
    func stop() throws -> URL { URL(fileURLWithPath: "/tmp/relay-fake.caf") }
}

actor FakeTranscriber: Transcribing {
    var text: String
    var prepareError: TranscriptionError?

    init(text: String) { self.text = text }
    func setPrepareError(_ error: TranscriptionError?) { prepareError = error }
    func prepare() async throws { if let prepareError { throw prepareError } }
    func transcribe(_ audio: URL) async throws -> String { text }
}

actor FakeRouter: IntentRouting {
    var outcome: RoutingDecision.Outcome
    private(set) var routeCount = 0

    init(outcome: RoutingDecision.Outcome) { self.outcome = outcome }
    func prepare(progress: @escaping @Sendable (String) -> Void) async throws {}
    func setThresholds(_ thresholds: RoutingThresholds) {}
    func route(_ transcript: String) async throws -> RoutingDecision {
        routeCount += 1
        return RoutingDecision(outcome: outcome, gateProbability: 0.9,
                               choiceProbabilities: [.openApp: 0.9], stateWasTruncated: false)
    }
}

@MainActor
final class FakeOpener: URLOpening {
    private(set) var opened: [URL] = []
    func open(_ url: URL) -> Bool {
        opened.append(url)
        return true
    }
}

actor FakeClaude: ClaudeJobRunning {
    private(set) var prompts: [String] = []
    private(set) var cleared: [URL] = []
    private var script: [ClaudeEvent] = []
    private var holdOpen = false
    private var running = false
    private var held: AsyncStream<ClaudeEvent>.Continuation?

    func setScript(_ events: [ClaudeEvent]) { script = events }
    func setHoldOpen(_ value: Bool) { holdOpen = value }
    func setRunning(_ value: Bool) { running = value }

    func run(prompt: String, project: URL) throws -> AsyncStream<ClaudeEvent> {
        prompts.append(prompt)
        let (stream, continuation) = AsyncStream<ClaudeEvent>.makeStream()
        for event in script { continuation.yield(event) }
        if holdOpen {
            held = continuation
            running = true
        } else {
            continuation.finish()
        }
        return stream
    }

    func release() {
        held?.finish()
        held = nil
        running = false
    }

    func stop() { release() }
    func clearSession(for project: URL) { cleared.append(project) }
    var isRunning: Bool { running }
}

final class MemoryLog: DecisionLogging {
    let entries = Mutex<[DecisionLogEntry]>([])
    func append(_ entry: DecisionLogEntry) { entries.withLock { $0.append(entry) } }
    var all: [DecisionLogEntry] { entries.withLock { $0 } }
}

actor FakeSystem: SystemControlling {
    private(set) var calls: [String] = []
    var currentVolume = 50
    var failure: SystemControlError?
    var muteFailure: SystemControlError?

    func failMute(with error: SystemControlError?) { muteFailure = error }
    func setCurrentVolume(_ value: Int) { currentVolume = value }
    func fail(with error: SystemControlError?) { failure = error }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func volume() throws -> Int { try record("volume()"); return currentVolume }
    func setVolume(_ percent: Int) throws { try record("setVolume(\(percent))"); currentVolume = percent }
    func setMuted(_ muted: Bool) throws {
        try record("setMuted(\(muted))")
        if let muteFailure { throw muteFailure }
    }
    func setBrightness(percent: Int) throws { try record("setBrightness(\(percent))") }
    func stepBrightness(up: Bool, presses: Int) throws { try record("stepBrightness(up: \(up), presses: \(presses))") }
    func setFocus(on: Bool) throws { try record("setFocus(\(on))") }
    func setDarkMode(_ mode: SwitchCommand) throws { try record("setDarkMode(\(mode))") }
    func lockScreen() throws { try record("lockScreen()") }
    func pressMediaKey(_ key: MediaKey) throws { try record("pressMediaKey(\(key))") }
    func takeScreenshot() throws -> URL {
        try record("takeScreenshot()")
        return URL(fileURLWithPath: "/Users/test/Desktop/Screenshot 2026-09-28 at 11.48.03.png")
    }
}

let safari = InstalledApp(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))

@MainActor
final class Harness {
    let recorder = FakeRecorder()
    let transcriber: FakeTranscriber
    let router: FakeRouter
    let opener = FakeOpener()
    let system = FakeSystem()
    let claude: FakeClaude?
    let log = MemoryLog()
    private(set) var notifications: [String] = []
    let project: URL
    private(set) var assistant: Assistant!

    init(transcript: String = "open safari", outcome: RoutingDecision.Outcome = .intent(.openApp), withClaude: Bool = true) {
        transcriber = FakeTranscriber(text: transcript)
        router = FakeRouter(outcome: outcome)
        claude = withClaude ? FakeClaude() : nil
        project = FileManager.default.temporaryDirectory.appendingPathComponent("relay-project-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let deps = AssistantDependencies(
            recorder: recorder, transcriber: transcriber, router: router,
            apps: { [safari] }, opener: opener, system: system, claude: claude, log: log,
            notify: { [weak self] title, _ in self?.notifications.append(title) })
        assistant = Assistant(dependencies: deps, activeProject: project)
    }

    /// Prepares, then runs one full hotkey press → press cycle.
    func speak() async {
        await assistant.prepare()
        await assistant.hotkeyPressed()
        await assistant.hotkeyPressed()
    }
}
