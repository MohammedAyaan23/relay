import AppKit
import AppSupport
import SwiftUI

/// Shows the hotkey and records a new one: press a combination with ⌘, ⌥, ⌃ or ⇧; Esc cancels.
struct HotkeyRecorder: View {
    @State private var hotkey = HotkeyStore.load(from: .standard)
    @State private var recording = false
    @State private var note: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Start/stop listening:")
                Button(recording ? "Press keys…" : hotkey.displayText) {
                    recording ? stop() : start()
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        note = "Press a shortcut, or Esc to cancel."
        recording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags
        let outcome = Hotkey.recordingOutcome(
            keyCode: UInt32(event.keyCode), command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift))
        switch outcome {
        case .cancel:
            note = nil
            stop()
        case .needsModifier:
            note = "Add ⌘, ⌥, ⌃ or ⇧"
        case .accept(let newHotkey):
            if HotkeyCenter.shared.register(newHotkey) {
                HotkeyStore.save(newHotkey, to: .standard)
                hotkey = newHotkey
                note = nil
            } else {
                note = "That shortcut is taken, so try another"
            }
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotkeyCenter.shared.resume()
    }
}
