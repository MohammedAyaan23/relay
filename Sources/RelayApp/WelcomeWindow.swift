import AppKit
import AppSupport
import SwiftUI

/// A normal window for the welcome steps. Closing it at any step counts as seen.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private let controller: AppController
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.title = "Welcome to Relay"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WelcomeView(controller: controller) { [weak window] in
                window?.close()
            })
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        WelcomeFlow.markSeen(.standard)
        // A fresh window (starting at step 1) next time "Welcome…" is chosen.
        window = nil
    }
}
