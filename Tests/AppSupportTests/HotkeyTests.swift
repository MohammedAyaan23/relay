import Foundation
import Testing
@testable import AppSupport

private func freshDefaults() -> UserDefaults {
    let name = "relay-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func defaultIsOptionSpace() {
    #expect(Hotkey.default == Hotkey(keyCode: 49, modifiers: 2048))
    #expect(Hotkey.default.displayText == "⌥Space")
}

@Test func displayTextOrdersModifiersControlOptionShiftCommand() {
    #expect(Hotkey(keyCode: 15, command: true, option: false, control: true, shift: false).displayText == "⌃⌘R")
    #expect(Hotkey(keyCode: 96, command: false, option: false, control: false, shift: true).displayText == "⇧F5")
    #expect(Hotkey(keyCode: 0, command: true, option: true, control: true, shift: true).displayText == "⌃⌥⇧⌘A")
    #expect(Hotkey(keyCode: 126, command: false, option: true, control: false, shift: false).displayText == "⌥↑")
}

@Test func unknownKeyShowsItsNumber() {
    #expect(Hotkey(keyCode: 200, modifiers: 2048).displayText == "⌥Key 200")
}

@Test func validityNeedsAModifierAndANonModifierKey() {
    #expect(Hotkey.default.isValid)
    #expect(!Hotkey(keyCode: 49, modifiers: 0).isValid)
    #expect(!Hotkey(keyCode: 58, modifiers: 2048).isValid) // the Option key itself
}

@Test func recordingOutcomes() {
    #expect(Hotkey.recordingOutcome(keyCode: 53, command: false, option: false, control: false, shift: false) == .cancel)
    #expect(Hotkey.recordingOutcome(keyCode: 15, command: false, option: false, control: false, shift: false) == .needsModifier)
    #expect(Hotkey.recordingOutcome(keyCode: 15, command: true, option: false, control: true, shift: false)
        == .accept(Hotkey(keyCode: 15, modifiers: 256 | 4096)))
    // Esc with a modifier is an ordinary shortcut.
    #expect(Hotkey.recordingOutcome(keyCode: 53, command: true, option: false, control: false, shift: false)
        == .accept(Hotkey(keyCode: 53, modifiers: 256)))
}

@Test func storeRoundTrips() {
    let defaults = freshDefaults()
    let hotkey = Hotkey(keyCode: 15, modifiers: 256 | 4096)
    HotkeyStore.save(hotkey, to: defaults)
    #expect(HotkeyStore.load(from: defaults) == hotkey)
}

@Test func emptyStoreGivesDefault() {
    #expect(HotkeyStore.load(from: freshDefaults()) == .default)
}

@Test func migratesKeyboardShortcutsValue() {
    let defaults = freshDefaults()
    defaults.set(#"{"carbonKeyCode":15,"carbonModifiers":4352}"#, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: defaults) == Hotkey(keyCode: 15, modifiers: 4352))
    #expect(defaults.string(forKey: HotkeyStore.key) != nil) // written under the new key
}

@Test func newKeyWinsOverLegacy() {
    let defaults = freshDefaults()
    defaults.set(#"{"carbonKeyCode":15,"carbonModifiers":4352}"#, forKey: HotkeyStore.legacyKey)
    HotkeyStore.save(Hotkey(keyCode: 0, modifiers: 256), to: defaults)
    #expect(HotkeyStore.load(from: defaults) == Hotkey(keyCode: 0, modifiers: 256))
}

@Test func corruptOrInvalidValuesGiveDefault() {
    let corrupt = freshDefaults()
    corrupt.set("not json", forKey: HotkeyStore.key)
    #expect(HotkeyStore.load(from: corrupt) == .default)

    let noModifier = freshDefaults()
    noModifier.set(#"{"keyCode":15,"modifiers":0}"#, forKey: HotkeyStore.key)
    #expect(HotkeyStore.load(from: noModifier) == .default)

    let invalidLegacy = freshDefaults()
    invalidLegacy.set(#"{"carbonKeyCode":15,"carbonModifiers":0}"#, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: invalidLegacy) == .default)
}

@Test func legacyNonStringValueGivesDefault() {
    let defaults = freshDefaults()
    defaults.set(false, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: defaults) == .default)
}
