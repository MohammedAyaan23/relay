import Actions
import Capture
import Extraction
import Foundation
import Observation
import Routing
import Transcription

/// How the last command turned out, for the HUD's icon.
public enum ResultKind: Sendable, Equatable {
    case success, info, problem
}

public enum PermissionKind: Sendable, Equatable {
    case microphone
    case speechRecognition
}

public struct AssistantDependencies {
    public var recorder: any AudioRecording
    public var transcriber: any Transcribing
    public var router: any IntentRouting
    public var apps: @Sendable () -> [InstalledApp]
    public var opener: any URLOpening
    /// nil when the claude executable couldn't be found.
    public var claude: (any ClaudeJobRunning)?
    public var log: any DecisionLogging
    /// Posts a user notification: (title, body).
    public var notify: @MainActor (String, String) -> Void

    public init(recorder: any AudioRecording, transcriber: any Transcribing, router: any IntentRouting,
                apps: @escaping @Sendable () -> [InstalledApp], opener: any URLOpening,
                claude: (any ClaudeJobRunning)?, log: any DecisionLogging,
                notify: @escaping @MainActor (String, String) -> Void) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.router = router
        self.apps = apps
        self.opener = opener
        self.claude = claude
        self.log = log
        self.notify = notify
    }
}

/// The central state machine: hotkey → listen → transcribe → route → act.
@MainActor @Observable
public final class Assistant {
    public enum Phase: Equatable, Sendable {
        case preparing, idle, listening, transcribing, routing, acting
    }

    static let noProject = "No active project. Pick one from the menu."
    static let claudeMissing = "Couldn't find the claude command. Set its path in Settings, then restart Relay."
    static let claudeBusy = "Claude is still working. Stop it first."

    public private(set) var phase: Phase = .preparing
    public private(set) var transcript: String?
    public private(set) var decision: RoutingDecision?
    public private(set) var message: String?
    public private(set) var resultKind: ResultKind?
    public private(set) var missingPermission: PermissionKind?
    /// Setup failed for a reason other than permissions (e.g. a dropped model download); offer a retry.
    public private(set) var prepareFailed = false
    public private(set) var claudeEvents: [ClaudeEvent] = []
    public private(set) var claudeRunning = false
    public var activeProject: URL?

    /// Microphone loudness (0…1) while listening, else 0. Not observed: the HUD polls it each frame.
    public var inputLevel: Float { phase == .listening ? deps.recorder.level : 0 }

    private let deps: AssistantDependencies
    private var matcher = AppMatcher(apps: [])
    private var claudeJob: Task<Void, Never>?
    /// The current job's error `result` text, and whether the user was already notified of a failure.
    private var claudeError: String?
    private var claudeFailureNotified = false

    public init(dependencies: AssistantDependencies, activeProject: URL? = nil) {
        deps = dependencies
        self.activeProject = activeProject
    }

    // MARK: Setup

    /// Requests permissions and loads models. The hotkey does nothing until this reaches `.idle`.
    public func prepare() async {
        phase = .preparing
        missingPermission = nil
        prepareFailed = false
        message = "Getting ready…"
        guard await deps.recorder.requestPermission() else {
            missingPermission = .microphone
            message = "Relay needs microphone access. Allow it in System Settings, then try again."
            return
        }
        do {
            try await deps.transcriber.prepare()
        } catch TranscriptionError.permissionDenied {
            missingPermission = .speechRecognition
            message = "Relay needs speech recognition access. Allow it in System Settings, then try again."
            return
        } catch {
            message = "Couldn't set up speech recognition: \(error.localizedDescription)"
            prepareFailed = true
            return
        }
        do {
            try await deps.router.prepare { text in
                Task { @MainActor [weak self] in self?.message = text }
            }
        } catch {
            message = "Couldn't load the Laya model: \(error.localizedDescription)"
            prepareFailed = true
            return
        }
        matcher = AppMatcher(apps: deps.apps())
        phase = .idle
        message = deps.claude == nil ? "Ready. (Claude Code wasn't found. Set its path in Settings.)" : "Ready."
    }

    public func setThresholds(_ thresholds: RoutingThresholds) async {
        await deps.router.setThresholds(thresholds)
    }

    // MARK: Hotkey

    /// First press starts listening; second press stops and runs the command. Ignored while busy.
    public func hotkeyPressed() async {
        switch phase {
        case .idle:
            do {
                try deps.recorder.start()
                transcript = nil
                decision = nil
                resultKind = nil
                phase = .listening
                message = "Listening… press the hotkey again when you're done."
            } catch CaptureError.permissionDenied {
                missingPermission = .microphone
                message = "Relay needs microphone access. Allow it in System Settings, then try again."
            } catch {
                message = "Couldn't start the microphone: \(error.localizedDescription)"
            }
        case .listening:
            let audio: URL
            do {
                audio = try deps.recorder.stop()
            } catch {
                finish("Recording failed: \(error.localizedDescription)", .problem)
                return
            }
            phase = .transcribing
            message = "Transcribing…"
            let text: String
            do {
                text = try await deps.transcriber.transcribe(audio)
            } catch {
                finish("Couldn't transcribe: \(error.localizedDescription)", .problem)
                return
            }
            try? FileManager.default.removeItem(at: audio)
            await handle(transcript: text)
        case .preparing, .transcribing, .routing, .acting:
            return
        }
    }

    // MARK: Commands

    /// Routes a transcript and performs the action. Public so it can be driven without a microphone.
    public func handle(transcript rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = text
        guard !text.isEmpty else { return finish("Didn't catch anything.", .info) }

        phase = .routing
        let decision: RoutingDecision
        do {
            decision = try await deps.router.route(text)
        } catch {
            return finish("Couldn't work out the command: \(error.localizedDescription)", .problem)
        }
        self.decision = decision

        let result: Outcome
        switch decision.outcome {
        case .notACommand:
            result = Outcome("Didn't sound like a command: “\(text)”", .info)
        case .ambiguous(let top):
            result = Outcome("Not sure what you meant. Maybe \(top.map(\.displayName).joined(separator: " or "))?", .info)
        case .intent(let intent):
            phase = .acting
            result = await perform(intent, text)
        }

        deps.log.append(DecisionLogEntry(
            timestamp: Date(), transcript: text, gateProbability: decision.gateProbability,
            choiceProbabilities: Dictionary(uniqueKeysWithValues: decision.choiceProbabilities.map { ($0.key.rawValue, $0.value) }),
            outcome: decision.outcome.logName, extracted: result.extracted,
            stateWasTruncated: decision.stateWasTruncated, result: result.message))
        finish(result.message, result.kind)
    }

    public func startNewClaudeSession() async {
        let result = await perform(.newClaudeSession, "")
        message = result.message
        resultKind = result.kind
    }

    public func stopClaude() async {
        await deps.claude?.stop()
    }

    func waitForClaudeJob() async {
        await claudeJob?.value
    }

    // MARK: Private

    private func finish(_ text: String, _ kind: ResultKind) {
        message = text
        resultKind = kind
        phase = .idle
    }

    private struct Outcome {
        let message: String
        let extracted: String?
        let kind: ResultKind

        init(_ message: String, _ kind: ResultKind, extracted: String? = nil) {
            self.message = message
            self.extracted = extracted
            self.kind = kind
        }
    }

    private func perform(_ intent: RoutedIntent, _ text: String) async -> Outcome {
        switch intent {
        case .openApp:
            switch matcher.match(text) {
            case .found(let app):
                let opened = deps.opener.open(app.url)
                return Outcome(opened ? "Opened \(app.name)." : "Couldn't open \(app.name).",
                               opened ? .success : .problem, extracted: app.name)
            case .notFound(let query, let suggestions):
                guard !query.isEmpty else { return Outcome("Which app should I open?", .info) }
                let hint = suggestions.isEmpty ? "" : " Closest: \(suggestions.joined(separator: ", "))."
                return Outcome("No app matching “\(query)”.\(hint)", .problem, extracted: query)
            }

        case .webSearch:
            guard let query = SearchQueryExtractor.query(from: text) else { return Outcome("What should I search for?", .info) }
            let opened = deps.opener.open(WebSearch.url(for: query))
            return Outcome(opened ? "Searching the web for “\(query)”." : "Couldn't open the browser.",
                           opened ? .success : .problem, extracted: query)

        case .newClaudeSession:
            guard let claude = deps.claude else { return Outcome(Self.claudeMissing, .problem) }
            guard let project = activeProject else { return Outcome(Self.noProject, .problem) }
            if await claude.isRunning { return Outcome(Self.claudeBusy, .problem) }
            do {
                try await claude.clearSession(for: project)
            } catch {
                return Outcome("Couldn't reset the Claude session: \(error.localizedDescription)", .problem)
            }
            claudeEvents = []
            return Outcome("Started a new Claude session for \(project.lastPathComponent).", .success)

        case .askClaude:
            guard let claude = deps.claude else { return Outcome(Self.claudeMissing, .problem) }
            guard let project = activeProject else { return Outcome(Self.noProject, .problem) }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return Outcome("The active project folder no longer exists: \(project.path). Pick another from the menu.", .problem)
            }
            guard let prompt = ClaudePromptExtractor.prompt(from: text) else { return Outcome("What should I ask Claude?", .info) }
            if await claude.isRunning { return Outcome(Self.claudeBusy, .problem, extracted: prompt) }
            let events: AsyncStream<ClaudeEvent>
            do {
                events = try await claude.run(prompt: prompt, project: project)
            } catch ClaudeRunnerError.busy {
                return Outcome(Self.claudeBusy, .problem, extracted: prompt)
            } catch {
                return Outcome("Couldn't start Claude: \(error.localizedDescription)", .problem, extracted: prompt)
            }
            claudeEvents = []
            claudeError = nil
            claudeFailureNotified = false
            claudeRunning = true
            claudeJob = Task { [weak self] in
                for await event in events { self?.receive(event) }
                self?.claudeJobEnded()
            }
            return Outcome("Claude is working on it in \(project.lastPathComponent)…", .success, extracted: prompt)
        }
    }

    private func claudeJobEnded() {
        claudeRunning = false
        if let claudeError, !claudeFailureNotified {
            deps.notify("Claude failed", claudeError)
        }
    }

    private func receive(_ event: ClaudeEvent) {
        if case .ignored = event { return }
        claudeEvents.append(event)
        switch event {
        case .finished(let result) where result.isError:
            // A failed exit usually follows; notify then (or when the job ends), not twice.
            claudeError = result.text ?? "no details"
            message = "Claude reported an error: \(claudeError!)"
        case .finished(let result):
            var summary = "Claude finished in \(result.durationMs / 1000)s ($\(String(format: "%.2f", result.costUSD)))."
            if !result.deniedTools.isEmpty { summary += " Blocked: \(result.deniedTools.joined(separator: "; "))." }
            message = summary
            deps.notify("Claude finished", result.text ?? summary)
        case .failed(let code, let tail):
            // Auth, credit and API errors leave stderr empty; the reason is in the error result.
            let reason = tail.isEmpty ? (claudeError ?? "no details") : tail
            message = "Claude failed (exit \(code)): \(reason)"
            deps.notify("Claude failed", reason)
            claudeFailureNotified = true
        case .stopped:
            message = "Stopped Claude."
        default:
            break
        }
    }
}
