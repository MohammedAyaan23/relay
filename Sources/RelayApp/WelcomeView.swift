import Actions
import AppSupport
import AssistantCore
import AVFoundation
import Speech
import SwiftUI

/// The three-step first-launch welcome: meet Relay, set up permissions and the model, try a command.
struct WelcomeView: View {
    let controller: AppController
    var onDone: () -> Void
    @State private var flow: WelcomeFlow
    @State private var microphone = PermissionRow.State.notAsked
    @State private var speech = PermissionRow.State.notAsked
    @State private var claudeFound: Bool?

    init(controller: AppController, startAt: WelcomeStep = .meet, onDone: @escaping () -> Void = {}) {
        self.controller = controller
        self.onDone = onDone
        _flow = State(initialValue: WelcomeFlow(step: startAt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch flow.step {
            case .meet: meet
            case .setup: setup
            case .tryIt: tryIt
            }
            Spacer(minLength: 0)
            HStack {
                if !flow.isFirst { Button("Back") { flow.back() } }
                Spacer()
                if flow.isLast {
                    Button("Done", action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { flow.next() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .task {
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var meet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Relay").font(.title2.bold())
            Text("Relay does things on your Mac when you ask out loud.")
            HotkeyRecorder()
            Text("Relay lives in the menu bar, look for its icon at the top right.")
                .foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up").font(.title2.bold())
            permissionRow("Microphone", state: microphone, kind: .microphone) {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    retryIfWaiting()
                }
            }
            permissionRow("Speech Recognition", state: speech, kind: .speechRecognition) {
                SFSpeechRecognizer.requestAuthorization { _ in
                    Task { @MainActor in retryIfWaiting() }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Laya model").frame(width: 150, alignment: .leading)
                if controller.assistant.prepareFailed {
                    Text(controller.assistant.message ?? "Couldn't load the model.").foregroundStyle(.secondary)
                    Button("Try again") { controller.retryPrepare() }
                } else if controller.assistant.phase == .preparing {
                    Text(controller.assistant.message ?? "Getting ready…").foregroundStyle(.secondary)
                } else {
                    Text("Ready ✓")
                }
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it").font(.title2.bold())
            Text("Press \(HotkeyStore.load(from: .standard).displayText), say \"open Safari\", then press it again.")
            Text("Also try: \"search the web for pasta recipes\", \"set volume to 30\", \"remind me to call mum at 5pm\".")
                .foregroundStyle(.secondary)
            Text("Optional").font(.headline).padding(.top, 6)
            HStack {
                Text("Claude Code:")
                switch claudeFound {
                case .some(true): Text("found ✓")
                case .some(false):
                    Text("not found")
                    Link("Install", destination: URL(string: "https://claude.com/product/claude-code")!)
                case .none: Text("checking…").foregroundStyle(.secondary)
                }
            }
            Text("Accessibility: asked the first time you use typing or window commands.")
            if ReleaseInfo.repository.isEmpty {
                Text("Brightness and Focus: Relay shows the setup steps the first time you ask.")
            } else {
                Link("Brightness and Focus: how to set them up",
                     destination: URL(string: "https://github.com/\(ReleaseInfo.repository)#brightness-and-focus")!)
            }
        }
        .task {
            let override = UserDefaults.standard.string(forKey: Preferences.claudePathOverride)
            claudeFound = await Task.detached { ClaudeLocator.locate(override: override) != nil }.value
        }
    }

    private func permissionRow(_ title: String, state: PermissionRow.State, kind: PermissionKind,
                               allow: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).frame(width: 150, alignment: .leading)
                if state == .granted { Text("✓") }
                if let button = state.buttonTitle {
                    Button(button) {
                        if state == .denied { controller.openPrivacySettings(for: kind) } else { allow() }
                    }
                }
            }
            if state != .granted {
                Text("Relay can't listen until this is allowed.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshPermissions() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        speech = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Once a permission is granted, finish the setup that stopped waiting for it.
    private func retryIfWaiting() {
        refreshPermissions()
        if controller.assistant.missingPermission != nil { controller.retryPrepare() }
    }
}
