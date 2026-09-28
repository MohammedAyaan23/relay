import Actions
import AppKit
import AssistantCore
import Capture
import Extraction
@preconcurrency import KeyboardShortcuts
import Observation
import Routing
import SystemControls
import Transcription

@MainActor
final class AppController {
    let assistant: Assistant
    private lazy var panel = PanelController(assistant: assistant, controller: self)
    private lazy var hud = HUDController(assistant: assistant)

    init() {
        Preferences.registerDefaults()
        let claudeURL = ClaudeLocator.locate(override: UserDefaults.standard.string(forKey: Preferences.claudePathOverride))
        let dependencies = AssistantDependencies(
            recorder: MicRecorder(),
            transcriber: SpeechTranscription(),
            router: LayaRouter(thresholds: Preferences.thresholds),
            apps: { AppIndex.scan() },
            opener: WorkspaceOpener(),
            system: MacSystemControls(),
            claude: claudeURL.map { ClaudeRunner(executable: $0, sessions: SessionStore(fileURL: SessionStore.defaultFileURL)) },
            log: DecisionLog(fileURL: DecisionLog.defaultFileURL),
            notify: { title, body in Notifier.post(title: title, body: body) })
        assistant = Assistant(dependencies: dependencies, activeProject: Preferences.activeProject)
    }

    func start() {
        Notifier.requestAuthorization()
        KeyboardShortcuts.onKeyUp(for: .toggleListening) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A light tap on the trackpad (if a finger is on it) confirms start/stop.
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                self.hud.present()
                Task {
                    await self.assistant.hotkeyPressed()
                    // Still listening: keep the pill. Otherwise show the result briefly, then fade.
                    if self.assistant.phase != .listening { self.hud.scheduleHide() }
                }
            }
        }
        watchForPanelWorthyChanges()
        hud.present()
        Task {
            await assistant.prepare()
            hud.scheduleHide()
        }
    }

    /// The panel opens by itself only when there's something to watch or fix: a Claude job starting,
    /// or a permission/setup problem that needs its buttons.
    private func watchForPanelWorthyChanges() {
        withObservationTracking {
            _ = assistant.claudeRunning
            _ = assistant.missingPermission
            _ = assistant.prepareFailed
            _ = assistant.missingShortcut
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.assistant.claudeRunning || self.assistant.missingPermission != nil || self.assistant.prepareFailed
                    || self.assistant.missingShortcut != nil {
                    self.panel.show()
                }
                self.watchForPanelWorthyChanges()
            }
        }
    }

    func showPanel() {
        panel.show()
    }

    func chooseProject() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Use as Active Project"
        NSApp.activate()
        guard picker.runModal() == .OK, let url = picker.url else { return }
        UserDefaults.standard.set(url.path, forKey: Preferences.activeProjectPath)
        assistant.activeProject = url
    }

    func applyThresholds() {
        Task { await assistant.setThresholds(Preferences.thresholds) }
    }

    func retryPrepare() {
        Task { await assistant.prepare() }
    }

    func openPrivacySettings(for kind: PermissionKind) {
        let anchor = switch kind {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    /// A signed shortcut file bundled in Relay.app, if one was added to Resources/Shortcuts.
    func bundledShortcut(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    /// Opens a bundled shortcut in Shortcuts' import dialog, or the Shortcuts app so the user can build it.
    func setUpShortcut(named name: String) {
        if let file = bundledShortcut(named: name) {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }

    func shutdown() async {
        await assistant.stopClaude()
    }
}
