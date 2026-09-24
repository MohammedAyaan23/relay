import Actions
import AppKit
import AssistantCore
import Capture
import Extraction
@preconcurrency import KeyboardShortcuts
import Routing
import Transcription

@MainActor
final class AppController {
    let assistant: Assistant
    private lazy var panel = PanelController(assistant: assistant, controller: self)

    init() {
        Preferences.registerDefaults()
        let claudeURL = ClaudeLocator.locate(override: UserDefaults.standard.string(forKey: Preferences.claudePathOverride))
        let dependencies = AssistantDependencies(
            recorder: MicRecorder(),
            transcriber: SpeechTranscription(),
            router: LayaRouter(thresholds: Preferences.thresholds),
            apps: { AppIndex.scan() },
            opener: WorkspaceOpener(),
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
                self.panel.show()
                Task { await self.assistant.hotkeyPressed() }
            }
        }
        panel.show()
        Task { await assistant.prepare() }
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
        let anchor = kind == .microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    func shutdown() async {
        await assistant.stopClaude()
    }
}
