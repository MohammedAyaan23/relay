import AppKit
import AssistantCore
import SwiftUI

/// A floating panel that stays on top without taking keyboard focus from the app you're typing in.
@MainActor
final class PanelController {
    private let panel: NSPanel

    init(assistant: Assistant, controller: AppController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.title = "Relay"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelView(assistant: assistant, controller: controller))
        panel.center()
        panel.setFrameAutosaveName("RelayPanel")
    }

    func show() {
        panel.orderFrontRegardless()
    }
}
