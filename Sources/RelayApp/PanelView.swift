import Actions
import AssistantCore
import Routing
import SwiftUI

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
