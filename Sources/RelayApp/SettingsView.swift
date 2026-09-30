import AssistantCore
import SwiftUI

struct SettingsView: View {
    let controller: AppController
    @AppStorage(Preferences.claudePathOverride) private var claudePath = ""
    @AppStorage(Preferences.gateThreshold) private var gate = 0.5
    @AppStorage(Preferences.choiceThreshold) private var choice = 0.35
    @AppStorage(Preferences.checkForUpdates) private var checkForUpdates = true
    @State private var historyCleared = false

    var body: some View {
        Form {
            HotkeyRecorder()
            TextField("claude path:", text: $claudePath, prompt: Text("found automatically"))
            Text("Restart Relay after changing the claude path.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $gate, in: 0.05...0.95) {
                Text("Command gate: \(gate, format: .number.precision(.fractionLength(2)))")
            }
            Slider(value: $choice, in: 0.05...0.95) {
                Text("Action choice: \(choice, format: .number.precision(.fractionLength(2)))")
            }
            HStack {
                Button("Clear command history") {
                    DecisionLog(fileURL: DecisionLog.defaultFileURL).clear()
                    historyCleared = true
                }
                if historyCleared { Text("Cleared").foregroundStyle(.secondary) }
            }
            Text("Relay keeps your last 500 command phrases on this Mac to improve routing. It never keeps "
                + "dictated text, notes, reminders or speech that wasn't a command.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if controller.updates.isConfigured {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Button("Check now") { Task { await controller.updates.checkNow() } }
                    if let update = controller.updates.available, controller.updates.manualStatus?.hasPrefix("Update") == true {
                        Link("Update available: v\(update.version)", destination: update.url)
                    } else if let status = controller.updates.manualStatus {
                        Text(status).foregroundStyle(.secondary)
                    }
                }
            }
            Text(AppInfo.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 440)
        .onChange(of: gate) { controller.applyThresholds() }
        .onChange(of: choice) { controller.applyThresholds() }
    }
}
