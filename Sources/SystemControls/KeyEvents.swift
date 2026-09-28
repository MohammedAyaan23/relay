import AppKit

/// Presses system keys the way the keyboard does. Posting events requires Accessibility permission.
enum KeyEvents {
    // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
    static let brightnessUp: Int32 = 2
    static let brightnessDown: Int32 = 3

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
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 12 /* kVK_ANSI_Q */, keyDown: isDown)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }
}
