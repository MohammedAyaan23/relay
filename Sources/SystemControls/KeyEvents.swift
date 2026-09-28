import AppKit

/// Presses system keys the way the keyboard does. Posting events requires Accessibility permission.
enum KeyEvents {
    // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
    static let brightnessUp: Int32 = 2
    static let brightnessDown: Int32 = 3
    static let illuminationUp: Int32 = 21   // keyboard backlight
    static let illuminationDown: Int32 = 22

    static func code(for key: MediaKey) -> Int32 {
        switch key {
        case .playPause: 16 // NX_KEYTYPE_PLAY
        case .next: 17      // NX_KEYTYPE_NEXT
        case .previous: 18  // NX_KEYTYPE_PREVIOUS
        }
    }

    /// Posts a media or brightness key press (down, then up) as a system-defined event.
    @MainActor static func pressSystemKey(_ code: Int32) {
        for isDown in [true, false] {
            let state: Int32 = isDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: Int((code << 16) | (state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// ⌃⌘Q, the system Lock Screen shortcut.
    @MainActor static func pressLockShortcut() {
        pressKey(12 /* kVK_ANSI_Q */, flags: [.maskControl, .maskCommand])
    }

    static func shortcut(for shortcut: WindowShortcut) -> (key: CGKeyCode, flags: CGEventFlags) {
        switch shortcut {
        case .minimize: (46 /* kVK_ANSI_M */, .maskCommand)
        case .fullScreen: (3 /* kVK_ANSI_F */, [.maskControl, .maskCommand])
        case .close: (13 /* kVK_ANSI_W */, .maskCommand)
        }
    }

    @MainActor static func press(_ shortcut: WindowShortcut) {
        let keys = self.shortcut(for: shortcut)
        pressKey(keys.key, flags: keys.flags)
    }

    /// Posts a key down and up with modifiers to the frontmost app.
    @MainActor static func pressKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
