import Actions
import AssistantCore
import Routing
import SwiftUI
import SystemControls

struct PanelView: View {
    let assistant: Assistant
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(phaseLabel).font(.headline)
                Spacer()
                if let project = assistant.activeProject {
                    Text(project.lastPathComponent).foregroundStyle(.secondary)
                }
            }
            if let message = assistant.message {
                Text(message).textSelection(.enabled)
            }
            if let kind = assistant.missingPermission {
                HStack {
                    Button("Open System Settings") { controller.openPrivacySettings(for: kind) }
                    Button("Try Again") { controller.retryPrepare() }
                }
            } else if assistant.prepareFailed {
                Button("Try Again") { controller.retryPrepare() }
            }
            if let shortcut = assistant.missingShortcut {
                ShortcutSetupView(name: shortcut, isBundled: controller.bundledShortcut(named: shortcut) != nil) {
                    controller.setUpShortcut(named: shortcut)
                }
            }
            if !assistant.fileMatches.isEmpty {
                FileMatchesView(matches: assistant.fileMatches) { match in
                    Task { await assistant.pick(match) }
                }
            }
            if !assistant.timers.isEmpty {
                TimersView(timers: assistant.timers) { timer in
                    Task { await assistant.cancelTimer(timer) }
                }
            }
            if let transcript = assistant.transcript, !transcript.isEmpty {
                Label(transcript, systemImage: "quote.bubble").foregroundStyle(.secondary)
            }
            if let decision = assistant.decision {
                Text(summary(of: decision)).font(.caption).foregroundStyle(.secondary)
            }
            if assistant.claudeRunning || !assistant.claudeEvents.isEmpty {
                Divider()
                HStack {
                    Text("Claude").font(.headline)
                    Spacer()
                    if assistant.claudeRunning {
                        ProgressView().controlSize(.small)
                        Button("Stop") { Task { await assistant.stopClaude() } }
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(assistant.claudeEvents.enumerated()), id: \.offset) { index, event in
                                ClaudeEventRow(event: event).id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: assistant.claudeEvents.count) { _, count in
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .task { await assistant.refreshTimers() }
        .frame(minWidth: 360, minHeight: 240)
    }

    private var phaseLabel: String {
        switch assistant.phase {
        case .preparing: "Getting ready"
        case .idle: "Ready"
        case .listening: "Listening…"
        case .transcribing: "Transcribing…"
        case .routing: "Thinking…"
        case .acting: "Working…"
        }
    }

    private func summary(of decision: RoutingDecision) -> String {
        let command = String(format: "command %.2f", decision.gateProbability)
        let top = decision.choiceProbabilities.sorted { $0.value > $1.value }.prefix(2)
            .map { "\($0.key.rawValue) \(String(format: "%.2f", $0.value))" }
        return ([command] + top).joined(separator: " · ")
    }
}

struct ClaudeEventRow: View {
    let event: ClaudeEvent

    var body: some View {
        switch event {
        case .text(let text):
            Text(text).textSelection(.enabled)
        case .toolUse(let name, let summary):
            Label(summary.isEmpty ? name : "\(name) \(summary)", systemImage: "wrench.and.screwdriver")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        case .toolResult(let isError):
            if isError {
                Label("Tool call failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .finished(let result):
            Label(String(format: "Done in %.1fs · $%.2f", Double(result.durationMs) / 1000, result.costUSD),
                  systemImage: result.isError ? "xmark.octagon" : "checkmark.seal")
                .font(.caption)
        case .failed(let code, _):
            Label("Exited with code \(code)", systemImage: "xmark.octagon").foregroundStyle(.red)
        case .stopped:
            Label("Stopped", systemImage: "stop.circle")
        case .sessionStarted, .ignored:
            EmptyView()
        }
    }
}

/// Explains how to create one of Relay's helper shortcuts (one action each).
struct ShortcutSetupView: View {
    let name: String
    let isBundled: Bool
    let action: () -> Void

    private var steps: [String] {
        switch name {
        case "Relay Brightness":
            ["In Shortcuts, create a new shortcut named “Relay Brightness”.",
             "Add the “Set Brightness” action.",
             "Click its brightness value and choose “Shortcut Input”."]
        case "Relay Focus On":
            ["In Shortcuts, create a new shortcut named “Relay Focus On”.",
             "Add the “Set Focus” action and set it to turn Do Not Disturb On.",
             "Create “Relay Focus Off” the same way, turning Do Not Disturb Off."]
        default:
            ["In Shortcuts, create a new shortcut named “\(name)”.",
             "Add the “Set Focus” action and set it to turn Do Not Disturb Off.",
             "Create “Relay Focus On” the same way, turning Do Not Disturb On."]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One-time setup: \(name)").font(.headline)
            if isBundled {
                Text("Click Add Shortcut, then Add in the Shortcuts window.")
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
                Text("Then say the command again.").foregroundStyle(.secondary)
            }
            Button(isBundled ? "Add Shortcut" : "Open Shortcuts", action: action)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The "Pick a file" list shown when a find/open/reveal request matched several files.
struct FileMatchesView: View {
    let matches: [FileMatch]
    let pick: (FileMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick a file").font(.headline)
            ForEach(matches, id: \.self) { match in
                Button { pick(match) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(match.name)
                        Text(Self.shortPath(match.url.deletingLastPathComponent()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// "/Users/me/Documents/Taxes" → "~/Documents/Taxes"; iCloud Drive paths read "iCloud Drive/…".
    static func shortPath(_ folder: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        let path = folder.path
        if path.hasPrefix(iCloud) { return "iCloud Drive" + path.dropFirst(iCloud.count) }
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Running timers with a live countdown and a ✕ to cancel each.
struct TimersView: View {
    let timers: [RelayTimer]
    let cancel: (RelayTimer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timers").font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(timers.filter { $0.endsAt > context.date }) { timer in
                        HStack {
                            Text(CaptureFormat.displayName(timer))
                            Spacer()
                            Text(Self.clock(timer.endsAt.timeIntervalSince(context.date))).monospacedDigit()
                            Button { cancel(timer) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// "8:59", or "1:05:00" for timers over an hour.
    static func clock(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
