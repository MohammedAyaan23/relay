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
}

actor FakeWorkspace: WorkspaceControlling {
    private(set) var calls: [String] = []
    var running = [InstalledApp(name: "Slack", url: URL(fileURLWithPath: "/Applications/Slack.app")),
                   InstalledApp(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))]
    var frontmost: String? = "Safari"
    var finderFolder: URL?
    var finderDenied = false
    var matches: [FileMatch] = []
    var screenshotResult = ScreenshotResult.saved(URL(fileURLWithPath: "/Users/test/Desktop/Screenshot.png"))
    var failure: SystemControlError?

    func setFrontmost(_ name: String?) { frontmost = name }
    func setFinderFolder(_ url: URL?) { finderFolder = url }
    func denyFinder() { finderDenied = true }
    func setMatches(_ list: [FileMatch]) { matches = list }
    func setScreenshotResult(_ result: ScreenshotResult) { screenshotResult = result }
    func fail(with error: SystemControlError?) { failure = error }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func runningApps() -> [InstalledApp] { running }
    func frontmostAppName() -> String? { frontmost }
    func quit(appNamed name: String) throws { try record("quit(\(name))") }
    func hide(appNamed name: String) throws { try record("hide(\(name))") }
    func sendWindowShortcut(_ shortcut: WindowShortcut) throws { try record("shortcut(\(shortcut))") }
    func frontFinderFolder() throws -> URL? {
        if finderDenied { throw SystemControlError.automationDenied("Finder") }
        return finderFolder
    }
    func createFolder(named name: String, in folder: URL) throws -> URL {
        try record("createFolder(\(name), \(folder.lastPathComponent))")
        return folder.appendingPathComponent(name)
    }
    func createFile(named name: String, in folder: URL) throws -> URL {
        try record("createFile(\(name), \(folder.lastPathComponent))")
        return folder.appendingPathComponent(name)
    }
    func searchFiles(_ query: String) throws -> [FileMatch] { try record("search(\(query))"); return matches }
    func open(_ url: URL) throws { try record("open(\(url.lastPathComponent))") }
    func reveal(_ url: URL) throws { try record("reveal(\(url.lastPathComponent))") }
    func captureScreenshot(_ options: ScreenshotOptions) throws -> ScreenshotResult {
        try record("screenshot(\(options.target), clipboard: \(options.toClipboard))")
        return screenshotResult
    }
}

actor FakeCapture: CaptureControlling {
    private(set) var calls: [String] = []
    var frontApp = "TextEdit"
    var failure: SystemControlError?
    var notificationsAllowed = true
    var running: [RelayTimer] = []

    func fail(with error: SystemControlError?) { failure = error }
    func setNotificationsAllowed(_ value: Bool) { notificationsAllowed = value }
    func setRunning(_ timers: [RelayTimer]) { running = timers }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func typeText(_ text: String) throws -> String { try record("type(\(text))"); return frontApp }
    func addNote(_ text: String) throws { try record("note(\(text))") }
    func addReminder(title: String, due: Date?) throws { try record("reminder(\(title), due: \(due != nil))") }
    func startTimer(name: String?, seconds: Int) throws -> TimerStart {
        try record("start(\(name ?? "-"), \(seconds))")
        let timer = RelayTimer(id: UUID(), name: name, endsAt: Date().addingTimeInterval(TimeInterval(seconds)))
        running.append(timer)
        return TimerStart(timer: timer, notificationsAllowed: notificationsAllowed)
    }
    func activeTimers() -> [RelayTimer] { running }
    func cancelTimer(id: UUID) {
        calls.append("cancel(\(running.first { $0.id == id }?.name ?? "-"))")
        running.removeAll { $0.id == id }
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
    let workspace = FakeWorkspace()
    let capture = FakeCapture()
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
            apps: { [safari] }, opener: opener, system: system, workspace: workspace, capture: capture, claude: claude, log: log,
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
