import AppKit
import AppSupport
import SwiftUI

/// `Relay --self-check`: draws every window Relay can show, then exits. `make release` runs it with this
/// checkout's `.build` folder hidden, so a view that needs a SwiftPM resource bundle crashes here, not on a
/// user's Mac.
@MainActor
enum SelfCheck {
    static var isRequested: Bool { CommandLine.arguments.contains("--self-check") }

    static func run(controller: AppController) -> Never {
        check("settings", SettingsView(controller: controller))
        check("panel", PanelView(assistant: controller.assistant, controller: controller))
        check("hud", HUDView(assistant: controller.assistant, model: HUDModel()))
        for step in WelcomeStep.allCases {
            check("welcome-\(step)", WelcomeView(controller: controller, startAt: step))
        }
        checkClosingWelcomeEndsRecording(controller: controller)
        _ = HotkeyStore.load(from: UserDefaults(suiteName: "relay-self-check")!)
        print("self-check: version \(AppInfo.version ?? "none")")
        print("self-check ok")
        exit(0)
    }

    /// Closing the welcome window while its recorder waits for keys must turn the hotkey back on.
    static func checkClosingWelcomeEndsRecording(controller: AppController) {
        let welcome = WelcomeWindow(controller: controller)
        welcome.show()
        HotkeyCenter.shared.beginRecording { _ in }
        welcome.close()
        guard !HotkeyCenter.shared.isRecording else {
            print("self-check FAILED: closing the welcome window left the hotkey recorder on")
            exit(1)
        }
        print("self-check: welcome close ok")
    }

    /// Puts the view in an off-screen window and draws it once, which runs its body and its AppKit views.
    static func check(_ name: String, _ view: some View) {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 480, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print("self-check: \(name) ok")
    }
}
