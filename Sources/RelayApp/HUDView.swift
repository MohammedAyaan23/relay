import AssistantCore
import SwiftUI

/// The listening pill: live waveform while listening, shimmer while working, then the result.
struct HUDView: View {
    let assistant: Assistant
    let model: HUDModel

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.isVisible {
                pill.transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: model.isVisible)
    }

    private var pill: some View {
        HStack(spacing: 10) { content }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 520)
            .fixedSize(horizontal: true, vertical: false)
            .glassEffect(.regular, in: .capsule)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: assistant.phase)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: assistant.message)
    }

    @ViewBuilder private var content: some View {
        switch assistant.phase {
        case .listening:
            PulsingDot()
            Waveform(assistant: assistant)
            Text("Listening")
        case .transcribing:
            ShimmerText(text: "Transcribing…")
        case .routing, .acting:
            ShimmerText(text: "Thinking…")
        case .preparing:
            ProgressView().controlSize(.small)
            Text(assistant.message ?? "Getting ready…").lineLimit(1)
        case .idle:
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: assistant.message)
                .transition(.scale.combined(with: .opacity))
            Text(assistant.message ?? "").lineLimit(2)
        }
    }

    private var icon: String {
        switch assistant.resultKind {
        case .success: "checkmark.circle.fill"
        case .problem: "exclamationmark.triangle.fill"
        case .info, nil: "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch assistant.resultKind {
        case .success: .green
        case .problem: .orange
        case .info, nil: .secondary
        }
    }
}

/// Bars that follow the microphone level, with a travelling ripple so they never look frozen.
private struct Waveform: View {
    let assistant: Assistant
    private let barCount = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let level = CGFloat(assistant.inputLevel)
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    let ripple = 0.55 + 0.45 * abs(sin(time * 7 + Double(index) * 0.8))
                    Capsule()
                        .frame(width: 3, height: 4 + 22 * level * ripple)
                }
            }
            .frame(height: 26)
            .foregroundStyle(.primary)
        }
    }
}

private struct PulsingDot: View {
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 9, height: 9)
            .phaseAnimator([1.0, 0.35]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.6) }
    }
}

/// Secondary-coloured text with a highlight sweeping across it.
private struct ShimmerText: View {
    let text: String
    @State private var offset: CGFloat = -0.6

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .overlay {
                LinearGradient(colors: [.clear, .primary, .clear],
                               startPoint: UnitPoint(x: offset, y: 0.5),
                               endPoint: UnitPoint(x: offset + 0.6, y: 0.5))
                    .mask { Text(text) }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { offset = 1.0 }
            }
    }
}
