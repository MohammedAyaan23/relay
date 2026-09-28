import Testing
@testable import Extraction

@Test func genericSwitchWords() {
    #expect(SwitchParser.parse("turn on the thing") == .on)
    #expect(SwitchParser.parse("switch it off") == .off)
    #expect(SwitchParser.parse("enable it") == .on)
    #expect(SwitchParser.parse("dark mode") == .toggle)
}

@Test(arguments: [
    ("switch to dark mode", SwitchCommand.on),
    ("turn dark mode off", .off),
    ("dark mode", .toggle),
    ("switch to light mode", .off),
    ("turn on light mode", .off),
    ("light mode please", .off),
    ("turn off light mode", .on),
])
func darkModeUnderstandsLightMode(_ transcript: String, _ expected: SwitchCommand) {
    #expect(SwitchParser.darkMode(transcript) == expected)
}

@Test(arguments: [
    ("turn on do not disturb", true),
    ("enable do not disturb for an hour", true),
    ("turn off do not disturb", false),
    ("stop do not disturb", false),
    ("i need to focus, silence notifications", true),
    ("turn off notifications", true),
    ("turn notifications back on", false),
])
func focusUnderstandsNotifications(_ transcript: String, _ expected: Bool) {
    #expect(SwitchParser.focusOn(transcript) == expected)
}

@Test func endOfTheDayIsNotAnOffSwitch() {
    #expect(SwitchParser.focusOn("enable do not disturb until the end of the day"))
}
