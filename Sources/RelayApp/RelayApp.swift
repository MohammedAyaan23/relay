import AppKit
import AssistantCore
import SwiftUI

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller, assistant: appDelegate.controller.assistant)
        } label: {
            Image(systemName: MenuBarIcon.name(for: appDelegate.controller.assistant))
        }
        Settings {
            SettingsView(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    /// Don't leave an orphaned `claude` process behind when quitting mid-job.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.assistant.claudeRunning else { return .terminateNow }
        Task {
            await controller.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

enum MenuBarIcon {
    @MainActor static func name(for assistant: Assistant) -> String {
        switch assistant.phase {
        case .preparing: "hourglass"
        case .listening: "mic.fill"
        case .transcribing, .routing, .acting: "ellipsis.circle"
        case .idle: assistant.claudeRunning ? "gearshape.2.fill" : "waveform"
        }
    }
}
