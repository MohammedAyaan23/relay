import AppKit
import AssistantCore
import SwiftUI

struct MenuContent: View {
    let controller: AppController
    let assistant: Assistant

    var body: some View {
        if let update = controller.updates.available {
            Button("Update available: v\(update.version)…") { NSWorkspace.shared.open(update.url) }
            Divider()
        }
        Text(assistant.activeProject.map { "Project: \($0.lastPathComponent)" } ?? "No active project")
        Button("Choose Active Project…") { controller.chooseProject() }
        Button("New Claude Session") { Task { await assistant.startNewClaudeSession() } }
            .disabled(assistant.activeProject == nil)
        Divider()
        Button("Show Panel") { controller.showPanel() }
        Button("Welcome…") { controller.showWelcome() }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Relay") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
