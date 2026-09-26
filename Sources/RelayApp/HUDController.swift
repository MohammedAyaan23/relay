import AppKit
import AssistantCore
import Observation
import SwiftUI

/// Whether the pill is showing. Hides are generation-counted so a newer `present()` cancels a pending hide.
@MainActor @Observable
final class HUDModel {
    var isVisible = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var onHidden: () -> Void = {}

    func present() {
        generation += 1
        isVisible = true
    }

    func scheduleHide(after delay: Duration) {
        generation += 1
        let scheduled = generation
        Task {
            try? await Task.sleep(for: delay)
            guard scheduled == generation else { return }
            isVisible = false
            // Let the fade-out finish before removing the window.
            try? await Task.sleep(for: .milliseconds(400))
            if scheduled == generation { onHidden() }
        }
    }
}

/// A click-through, non-activating glass pill at the bottom centre of the screen with the mouse.
@MainActor
final class HUDController {
    private static let size = NSSize(width: 560, height: 120)
    private let panel: NSPanel
    private let model = HUDModel()

    init(assistant: Assistant) {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDView(assistant: assistant, model: model))
        model.onHidden = { [weak self] in self?.panel.orderOut(nil) }
    }

    func present() {
        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
        }
        model.present()
    }

    /// Keep the result on screen long enough to read, then fade out.
    func scheduleHide() {
        model.scheduleHide(after: .seconds(2.5))
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - Self.size.width / 2, y: area.minY + 40))
    }
}
