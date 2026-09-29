import AppSupport
import Carbon.HIToolbox

/// The global hotkey, through Carbon's RegisterEventHotKey (no permission needed).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onPress: () -> Void = {}
    /// The hotkey Relay wants, kept while suspended for recording.
    private(set) var current: Hotkey?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Replaces the hotkey. If the new one can't be registered, the previous one is put back and this returns false.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        installHandler()
        let previous = current
        unregisterRef()
        if registerRef(hotkey) {
            current = hotkey
            return true
        }
        if let previous, registerRef(previous) { current = previous }
        return false
    }

    /// Stops listening for the hotkey (while the recorder takes a key press).
    func suspend() {
        unregisterRef()
    }

    /// Listens for the current hotkey again after `suspend()`.
    func resume() {
        if ref == nil, let current { _ = registerRef(current) }
    }

    private func registerRef(_ hotkey: Hotkey) -> Bool {
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x524C_4159), id: 1) // "RLAY"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        ref = newRef
        return true
    }

    private func unregisterRef() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotkeyCenter.shared.onPress() }
            return noErr
        }, 1, &type, nil, &handler)
    }
}
