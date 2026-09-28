import AssistantCore
import HUDKit
import SwiftUI

/// The listening pill: living goo while listening, orbiting goo while working, then a coloured
/// droplet with the result. Falls back to still colour and fades when Reduce Motion is on.
struct HUDView: View {
    let assistant: Assistant
    let model: HUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.isVisible {
                pill.transition(pillTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 20)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.45),
                   value: model.isVisible)
    }

    // MARK: Pill

    private var pill: some View {
        HStack(spacing: 12) {
            GooView(mode: gooMode, tint: resultTint, reduceMotion: reduceMotion) { Double(assistant.inputLevel) }
                .frame(width: gooWidth, height: 40)
                .overlay { resultIcon }
            label
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: glowColor.opacity(0.45), radius: 18, y: 4)
        // Squash-and-stretch as the droplet lands.
        .keyframeAnimator(initialValue: Squash(), trigger: reduceMotion ? 0 : model.appearCount) { content, squash in
            content.scaleEffect(x: squash.x, y: squash.y, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(0.7, duration: 0.01)
                SpringKeyframe(1.12, duration: 0.18)
                SpringKeyframe(0.96, duration: 0.14)
                SpringKeyframe(1, duration: 0.22)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(1.3, duration: 0.01)
                SpringKeyframe(0.88, duration: 0.18)
                SpringKeyframe(1.04, duration: 0.14)
                SpringKeyframe(1, duration: 0.22)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: gooMode)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: assistant.message)
    }

    private var pillTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        // Rises from the screen edge as a droplet; drips back down when done.
        return .asymmetric(
            insertion: .scale(scale: 0.2, anchor: .bottom).combined(with: .offset(y: 50)).combined(with: .opacity),
            removal: .scale(scale: 0.15, anchor: .bottom).combined(with: .offset(y: 60)).combined(with: .opacity))
    }

    @ViewBuilder private var label: some View {
        Group {
            switch assistant.phase {
            case .listening:
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("Listening")
                }
            case .transcribing:
                ShimmerText(text: "Transcribing…")
            case .routing, .acting:
                ShimmerText(text: "Thinking…")
            case .preparing:
                Text(assistant.message ?? "Getting ready…").lineLimit(1)
            case .idle:
                HStack(spacing: 10) {
                    Text(assistant.message ?? "")
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320, alignment: .leading)
                    if let level = assistant.resultLevel {
                        LevelBar(level: level)
                    }
                }
            }
        }
        .id(labelKey)
        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
    }

    @ViewBuilder private var resultIcon: some View {
        if gooMode == .result {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: assistant.message)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: State mapping

    private var gooMode: GooMode {
        switch assistant.phase {
        case .listening: .listening
        case .transcribing, .routing, .acting: .thinking
        case .preparing: .idle
        case .idle: assistant.resultKind == nil ? .idle : .result
        }
    }

    private var gooWidth: CGFloat {
        switch gooMode {
        case .listening: 120
        case .thinking: 64
        case .idle, .result: 40
        }
    }

    private var labelKey: String {
        "\(gooMode)|\(assistant.phase == .idle ? assistant.message ?? "" : "\(assistant.phase)")"
    }

    /// Solid droplet colour for results; nil means the flowing aurora.
    private var resultTint: Color? {
        guard gooMode == .result else { return nil }
        switch assistant.resultKind {
        case .success: return .green
        case .problem: return .orange
        case .info, nil: return .gray
        }
    }

    private var glowColor: Color { resultTint ?? .purple }

    private var iconName: String {
        switch assistant.resultKind {
        case .success: "checkmark"
        case .problem: "exclamationmark"
        case .info, nil: "info"
        }
    }
}

private struct Squash {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

// MARK: Goo

/// Metaballs: white blobs are blurred then alpha-thresholded, so touching blobs melt together.
/// The resulting shape masks a slowly rotating aurora gradient (or a solid result colour).
private struct GooView: View {
    let mode: GooMode
    let tint: Color?
    let reduceMotion: Bool
    let level: @MainActor () -> Double

    @State private var previousMode: GooMode = .idle
    @State private var modeChangedAt: TimeInterval = 0
    @State private var smoothing = LevelSmoothing()
    private let morphDuration: TimeInterval = 0.45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let shape = goo(now: now)
            fill(now: now)
                .mask { shape }
                .background {
                    // Soft glow in the same colours, bleeding out from the goo.
                    fill(now: now).mask { shape }.blur(radius: 10).opacity(0.7)
                }
        }
        .onChange(of: mode) { oldMode, _ in
            previousMode = oldMode
            modeChangedAt = Date.now.timeIntervalSinceReferenceDate
        }
    }

    private func fill(now: TimeInterval) -> some View {
        ZStack {
            AngularGradient(colors: [.blue, .purple, .pink, .orange, .cyan, .blue], center: .center,
                            angle: .degrees(reduceMotion ? 0 : (now * 60).truncatingRemainder(dividingBy: 360)))
                .opacity(tint == nil ? 1 : 0)
            (tint ?? .clear).opacity(tint == nil ? 0 : 1)
        }
    }

    private func goo(now: TimeInterval) -> some View {
        let level = reduceMotion ? level() : smoothing.advance(toward: level(), at: now)
        let progress = reduceMotion ? 1 : min(1, (now - modeChangedAt) / morphDuration)
        let eased = progress * progress * (3 - 2 * progress) // smoothstep
        return Canvas { context, size in
            let layout = GooLayout(size: size)
            var blobs = layout.blobs(mode: mode, level: level, time: now, reduceMotion: reduceMotion)
            if eased < 1 {
                let from = layout.blobs(mode: previousMode, level: level, time: now, reduceMotion: reduceMotion)
                blobs = GooLayout.blend(from: from, to: blobs, progress: eased)
            }
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: 5))
            context.drawLayer { layer in
                for blob in blobs {
                    let rect = CGRect(x: blob.center.x - blob.radius, y: blob.center.y - blob.radius,
                                      width: blob.radius * 2, height: blob.radius * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
    }
}

/// Keeps the level spring's state across frames. A class, so advancing it while drawing doesn't
/// trigger a SwiftUI state update.
@MainActor
private final class LevelSmoothing {
    private var spring = LevelSpring()
    private var lastTime: TimeInterval?

    func advance(toward target: Double, at time: TimeInterval) -> Double {
        defer { lastTime = time }
        guard let lastTime else { return spring.step(toward: target, dt: 1.0 / 60) }
        return spring.step(toward: target, dt: time - lastTime)
    }
}

// MARK: Small pieces

private struct PulsingDot: View {
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
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

/// A small capsule that fills to the result level, like macOS's own volume overlay.
private struct LevelBar: View {
    let level: Double
    @State private var shown: Double = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.secondary.opacity(0.25))
            Capsule().fill(.primary).frame(width: 72 * shown)
        }
        .frame(width: 72, height: 6)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { shown = level } }
        .onChange(of: level) { _, new in withAnimation(.spring(duration: 0.5, bounce: 0.3)) { shown = new } }
    }
}
