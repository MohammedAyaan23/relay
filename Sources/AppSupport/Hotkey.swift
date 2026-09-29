/// A global shortcut as Carbon sees it: a virtual key code plus a Carbon modifier mask.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    private static let allModifiers = command | shift | option | control

    public static let `default` = Hotkey(keyCode: 49, modifiers: option) // ⌥Space

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, command: Bool, option: Bool, control: Bool, shift: Bool) {
        var mask: UInt32 = 0
        if command { mask |= Self.command }
        if option { mask |= Self.option }
        if control { mask |= Self.control }
        if shift { mask |= Self.shift }
        self.init(keyCode: keyCode, modifiers: mask)
    }

    /// At least one of ⌘⌥⌃⇧, on a key that isn't itself a modifier.
    public var isValid: Bool {
        modifiers & Self.allModifiers != 0 && !Self.modifierKeyCodes.contains(keyCode)
    }

    /// e.g. "⌥Space", "⌃⌘R".
    public var displayText: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// What the recorder does with a key press.
    public static func recordingOutcome(keyCode: UInt32, command: Bool, option: Bool, control: Bool, shift: Bool)
        -> RecordingOutcome {
        let hotkey = Hotkey(keyCode: keyCode, command: command, option: option, control: control, shift: shift)
        if hotkey.modifiers == 0 { return keyCode == 53 ? .cancel : .needsModifier }
        return hotkey.isValid ? .accept(hotkey) : .needsModifier
    }

    static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// ANSI-layout names for Carbon virtual key codes.
    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

public enum RecordingOutcome: Equatable, Sendable {
    case cancel
    case needsModifier
    case accept(Hotkey)
}
