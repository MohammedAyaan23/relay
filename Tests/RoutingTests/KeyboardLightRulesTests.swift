import Testing
@testable import Routing

@Test(arguments: [
    "keyboard brighter",
    "make the keyboard dimmer",
    "turn the keyboard light off",
    "keyboard backlight to 30 percent",
    "dim the keyboard",
    "keyboard lights on",
    "set keyboard brightness to max",
])
func keyboardLightCommandsMatch(_ transcript: String) {
    #expect(CommandRules.match(transcript) == .keyboardLight)
}

@Test func screenAndOtherKeyboardPhrasesAreNotKeyboardLight() {
    #expect(CommandRules.match("make the screen brighter") == .brightness)
    #expect(CommandRules.match("google mechanical keyboards") == nil)
    #expect(CommandRules.match("open keyboard settings") == nil)
}
