import SwiftUI

struct SettingsView: View {
    let controller: AppController
    @AppStorage(Preferences.claudePathOverride) private var claudePath = ""
    @AppStorage(Preferences.gateThreshold) private var gate = 0.5
    @AppStorage(Preferences.choiceThreshold) private var choice = 0.35

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
