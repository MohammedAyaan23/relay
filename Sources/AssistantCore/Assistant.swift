import Actions
import Capture
import Extraction
import Foundation
import Observation
import Routing
import SystemControls
import Transcription

/// How the last command turned out, for the HUD's icon.
public enum ResultKind: Sendable, Equatable {
    case success, info, problem
}

public enum FileMatchAction: Sendable, Equatable {
    case open
    case reveal
}

public enum PermissionKind: Sendable, Equatable {
    case microphone
    case speechRecognition
    case accessibility
    case screenRecording
    case automation
}

public struct AssistantDependencies {
    public var recorder: any AudioRecording
    public var transcriber: any Transcribing
    public var router: any IntentRouting
    public var apps: @Sendable () -> [InstalledApp]
    public var opener: any URLOpening
    public var system: any SystemControlling
    public var workspace: any WorkspaceControlling
    /// nil when the claude executable couldn't be found.
    public var claude: (any ClaudeJobRunning)?
    public var log: any DecisionLogging
    /// Posts a user notification: (title, body).
    public var notify: @MainActor (String, String) -> Void

    public init(recorder: any AudioRecording, transcriber: any Transcribing, router: any IntentRouting,
                apps: @escaping @Sendable () -> [InstalledApp], opener: any URLOpening, system: any SystemControlling, workspace: any WorkspaceControlling,
                claude: (any ClaudeJobRunning)?, log: any DecisionLogging,
                notify: @escaping @MainActor (String, String) -> Void) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.router = router
        self.apps = apps
        self.opener = opener
        self.system = system
        self.workspace = workspace
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
    /// 0…1 for results with a known level (volume, brightness set), shown as a bar in the pill.
    public private(set) var resultLevel: Double?
    /// The helper shortcut the user needs to set up, e.g. "Relay Brightness".
    public private(set) var missingShortcut: String?
    /// Files matching a find/open/reveal request when there was more than one; the panel lists them.
    public private(set) var fileMatches: [FileMatch] = []
    public private(set) var fileMatchAction: FileMatchAction = .open
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
                resultLevel = nil
                missingShortcut = nil
                fileMatches = []
                missingPermission = nil
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

        case .volume:
            guard let command = LevelParser.parse(text) else {
                return Outcome("What volume? Try a percentage, like 40 percent.", .info)
            }
            return await control("change the volume") { try await self.changeVolume(command) }

        case .brightness:
            guard let command = LevelParser.parse(text), command != .mute, command != .unmute else {
                return Outcome("What brightness? Try a percentage, like 70 percent.", .info)
            }
            return await control("change the brightness") { try await self.changeBrightness(command) }

        case .darkMode:
            let mode = SwitchParser.darkMode(text)
            return await control("switch dark mode") {
                try await self.deps.system.setDarkMode(mode)
                let message = switch mode {
                case .on: "Dark mode on"
                case .off: "Dark mode off"
                case .toggle: "Switched appearance"
                }
                return Outcome(message, .success)
            }

        case .focus:
            let on = SwitchParser.focusOn(text)
            return await control("change Do Not Disturb") {
                try await self.deps.system.setFocus(on: on)
                return Outcome(on ? "Do Not Disturb on" : "Do Not Disturb off", .success)
            }

        case .lock:
            return await control("lock the screen") {
                try await self.deps.system.lockScreen()
                return Outcome("Locking…", .success)
            }

        case .screenshot:
            let options = ScreenshotOptionsParser.parse(text)
            let kind = switch options.target {
            case .screen: "Screenshot"
            case .window: "Window screenshot"
            case .area: "Area screenshot"
            }
            return await control("take a screenshot") {
                switch try await self.deps.workspace.captureScreenshot(options) {
                case .saved(let file):
                    if options.openAfter { try await self.deps.workspace.open(file) }
                    return Outcome("\(kind) saved to \(file.deletingLastPathComponent().lastPathComponent)", .success)
                case .copied:
                    return Outcome("\(kind) copied to clipboard", .success)
                case .cancelled:
                    return Outcome("Screenshot cancelled", .info)
                }
            }

        case .mediaPlayPause:
            return await control("play or pause") {
                try await self.deps.system.pressMediaKey(.playPause)
                return Outcome("Play/Pause", .success)
            }

        case .mediaNext:
            return await control("skip to the next track") {
                try await self.deps.system.pressMediaKey(.next)
                return Outcome("Next track", .success)
            }

        case .mediaPrevious:
            return await control("go to the previous track") {
                try await self.deps.system.pressMediaKey(.previous)
                return Outcome("Previous track", .success)
            }

        case .quitApp, .hideApp:
            let quitting = intent == .quitApp
            return await control(quitting ? "quit" : "hide") {
                let name = try await self.resolveApp(AppTargetParser.parse(text))
                if quitting {
                    try await self.deps.workspace.quit(appNamed: name)
                } else {
                    try await self.deps.workspace.hide(appNamed: name)
                }
                return Outcome(quitting ? "Quit \(name)" : "Hid \(name)", .success, extracted: name)
            }

        case .minimizeWindow, .fullScreen, .closeWindow:
            let shortcut: WindowShortcut = intent == .minimizeWindow ? .minimize : intent == .fullScreen ? .fullScreen : .close
            let verb = intent == .minimizeWindow ? "minimize" : intent == .fullScreen ? "make full screen" : "close"
            return await control(verb) {
                let front = await self.deps.workspace.frontmostAppName()
                // "close the Safari window" must not close whatever else happens to be in front.
                if case .named(let spoken) = AppTargetParser.parse(text) {
                    let frontApp = front.map { [InstalledApp(name: $0, url: URL(fileURLWithPath: "/"))] } ?? []
                    guard case .found(_) = AppMatcher(apps: frontApp).match(spoken) else {
                        return Outcome("\(spoken.capitalized) isn't in front.", .problem)
                    }
                }
                let app = front ?? "the window"
                try await self.deps.workspace.sendWindowShortcut(shortcut)
                let message = switch shortcut {
                case .minimize: "Minimized \(app)"
                case .fullScreen: "Toggled full screen"
                case .close: "Closed window"
                }
                return Outcome(message, .success)
            }

        case .createFolder, .createFile:
            let isFolder = intent == .createFolder
            let request = FileRequestParser.parse(text)
            guard let name = request.name else {
                return Outcome(isFolder ? "What should the folder be called?" : "What should the file be called?", .info)
            }
            return await control("create “\(name)”") {
                let (folder, note) = await self.creationFolder(for: request.location)
                let place = Self.placeDescription(folder)
                if isFolder {
                    let url = try await self.deps.workspace.createFolder(named: name, in: folder)
                    return Outcome("Created folder “\(url.lastPathComponent)” \(place)\(note)", .success, extracted: url.path)
                }
                let fileName = "\(name).\(request.fileExtension ?? "txt")"
                let url = try await self.deps.workspace.createFile(named: fileName, in: folder)
                return Outcome("Created “\(url.lastPathComponent)” \(place)\(note)", .success, extracted: url.path)
            }

        case .openFile, .findFile, .revealFile:
            guard let query = FileRequestParser.query(text) else { return Outcome("Which file?", .info) }
            if let place = FileLocation(rawValue: query) {
                let name = Self.folderName(place)
                if intent == .openFile {
                    return await control("open \(name)") {
                        try await self.deps.workspace.open(Self.url(for: place))
                        return Outcome("Opened \(name)", .success)
                    }
                }
                return await control("show \(name)") {
                    try await self.deps.workspace.reveal(Self.url(for: place))
                    return Outcome("Showed \(name) in Finder", .success)
                }
            }
            let action: FileMatchAction = intent == .openFile ? .open : .reveal
            return await control("search your files") {
                let matches = try await self.deps.workspace.searchFiles(query)
                switch matches.count {
                case 0:
                    return Outcome("No files matching “\(query)”.", .info, extracted: query)
                case 1:
                    return try await self.act(on: matches[0], action)
                default:
                    self.fileMatches = matches
                    self.fileMatchAction = action
                    return Outcome("Found \(matches.count) files matching “\(query)”. Pick one in the panel.",
                                   .info, extracted: query)
                }
            }
        }
    }

    private func changeVolume(_ command: LevelCommand) async throws -> Outcome {
        let system = deps.system
        let level: Int
        switch command {
        case .mute:
            do {
                try await system.setMuted(true)
                return Outcome("Muted", .success)
            } catch SystemControlError.noVolumeControl {
                // Some USB devices have volume but no mute control: silence them instead.
                try await system.setVolume(0)
                level = 0
            }
        case .unmute:
            try await system.setMuted(false)
            resultLevel = Double(try await system.volume()) / 100
            return Outcome("Unmuted", .success)
        case .set(let percent):
            try await system.setVolume(percent)
            if percent > 0 { try await unmuteIfPossible() }
            level = percent
        case .up(let step):
            level = min(100, try await system.volume() + step)
            try await unmuteIfPossible()
            try await system.setVolume(level)
        case .down(let step):
            level = max(0, try await system.volume() - step)
            try await system.setVolume(level)
        }
        resultLevel = Double(level) / 100
        return Outcome("Volume \(level)%", .success)
    }

    /// Unmutes before raising the volume; devices without a mute control are simply left as they are.
    private func unmuteIfPossible() async throws {
        do {
            try await deps.system.setMuted(false)
        } catch SystemControlError.noVolumeControl {}
    }

    private func changeBrightness(_ command: LevelCommand) async throws -> Outcome {
        switch command {
        case .set(let percent):
            try await deps.system.setBrightness(percent: percent)
            resultLevel = Double(percent) / 100
            return Outcome("Brightness \(percent)%", .success)
        case .up(let step), .down(let step):
            var up = false
            if case .up = command { up = true }
            try await deps.system.stepBrightness(up: up, presses: step <= 6 ? 1 : 2)
            return Outcome(up ? "Brighter" : "Dimmer", .success)
        case .mute, .unmute:
            return Outcome("What brightness? Try a percentage, like 70 percent.", .info)
        }
    }

    /// Runs a system action, turning its errors into the messages from spec §5.
    private func control(_ action: String, _ body: () async throws -> Outcome) async -> Outcome {
        do {
            return try await body()
        } catch let error as SystemControlError {
            switch error {
            case .noVolumeControl:
                return Outcome("This audio device doesn't allow volume control.", .problem)
            case .shortcutMissing(let name):
                missingShortcut = name
                let feature = name == ShortcutsBridge.brightness ? "Brightness" : "Do Not Disturb"
                return Outcome("\(feature) needs a one-time setup.", .info)
            case .shortcutFailed(let name, let reason):
                return Outcome("The \(name) shortcut failed: \(reason)", .problem)
            case .automationDenied:
                missingPermission = .automation
                return Outcome("Relay needs permission to control System Events for dark mode.", .problem)
            case .accessibilityDenied:
                missingPermission = .accessibility
                return Outcome("Relay needs Accessibility access to press keys for you.", .problem)
            case .screenRecordingDenied:
                missingPermission = .screenRecording
                return Outcome("Relay needs Screen Recording permission to take screenshots. Allow it, then quit and reopen Relay.", .problem)
            case .failed(let reason):
                return Outcome("Couldn't \(action): \(reason)", .problem)
            case .appNotRunning(let name):
                return Outcome("\(name) isn't running.", .problem)
            case .noFrontWindow:
                return Outcome("There's no app window in front to \(action).", .problem)
            case .searchFailed(let reason):
                return Outcome("Couldn't search your files: \(reason)", .problem)
            }
        } catch let error as NoMatchingApp {
            let running = error.running.isEmpty ? "" : " Running: \(error.running.joined(separator: ", "))."
            return Outcome("\(error.name) isn't running.\(running)", .problem)
        } catch {
            return Outcome("Couldn't \(action): \(error.localizedDescription)", .problem)
        }
    }

    /// Opens or reveals one file the user picked from the panel list.
    public func pick(_ match: FileMatch) async {
        guard FileManager.default.fileExists(atPath: match.url.path) else {
            message = "That file is no longer there."
            resultKind = .problem
            return
        }
        let action = fileMatchAction
        let result = await control(action == .open ? "open “\(match.name)”" : "show “\(match.name)”") {
            try await self.act(on: match, action)
        }
        message = result.message
        resultKind = result.kind
        if result.kind == .success { fileMatches = [] }
    }

    private func act(on match: FileMatch, _ action: FileMatchAction) async throws -> Outcome {
        switch action {
        case .open:
            try await deps.workspace.open(match.url)
            return Outcome("Opened “\(match.name)”", .success, extracted: match.url.path)
        case .reveal:
            try await deps.workspace.reveal(match.url)
            return Outcome("Showed “\(match.name)” in Finder", .success, extracted: match.url.path)
        }
    }

    private struct NoMatchingApp: Error {
        let name: String
        let running: [String]
    }

    private func resolveApp(_ target: AppTarget) async throws -> String {
        switch target {
        case .frontmost:
            guard let name = await deps.workspace.frontmostAppName() else { throw SystemControlError.noFrontWindow }
            return name
        case .named(let spoken):
            switch AppMatcher(apps: await deps.workspace.runningApps()).match(spoken) {
            case .found(let app):
                return app.name
            case .notFound(let query, let suggestions):
                throw NoMatchingApp(name: (query.isEmpty ? spoken : query).capitalized, running: suggestions)
            }
        }
    }

    static let finderNote = " (allow Relay to control Finder to use the open Finder window)"

    /// Where to create: a spoken place, else the front Finder window's folder, else the Desktop.
    private func creationFolder(for location: FileLocation?) async -> (URL, String) {
        if let location { return (Self.url(for: location), "") }
        do {
            if let finder = try await deps.workspace.frontFinderFolder() { return (finder, "") }
        } catch SystemControlError.automationDenied {
            return (Self.url(for: .desktop), Self.finderNote)
        } catch {}
        return (Self.url(for: .desktop), "")
    }

    static func url(for location: FileLocation) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return location == .home ? home : home.appendingPathComponent(folderName(location))
    }

    static func folderName(_ location: FileLocation) -> String {
        switch location {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .home: "Home"
        }
    }

    static func placeDescription(_ folder: URL) -> String {
        folder == url(for: .desktop) ? "on Desktop" : "in \(folder.lastPathComponent)"
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
