import Testing
@testable import Extraction

@Test(arguments: [
    ("set volume to 40 percent", LevelCommand.set(40)),
    ("volume 40%", .set(40)),
    ("brightness to forty five percent", .set(45)),
    ("set the volume to one hundred", .set(100)),
    ("volume to 150", .set(100)),
    ("half volume", .set(50)),
    ("brightness all the way up", .set(100)),
    ("volume to max", .set(100)),
    ("turn the volume all the way down", .set(0)),
])
func absoluteLevels(_ transcript: String, _ expected: LevelCommand) {
    #expect(LevelParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("turn the volume up", LevelCommand.up(10)),
    ("crank up the volume", .up(10)),
    ("it's too quiet", .up(10)),
    ("the screen is too dark", .up(10)),
    ("a bit louder", .up(6)),
    ("make it slightly brighter", .up(6)),
    ("it's too loud, bring it down a bit", .down(6)),
    ("lower the sound", .down(10)),
    ("dim the display", .down(10)),
    ("the screen is too bright", .down(10)),
])
func relativeLevels(_ transcript: String, _ expected: LevelCommand) {
    #expect(LevelParser.parse(transcript) == expected)
}

@Test func muteBeatsDirectionWords() {
    #expect(LevelParser.parse("mute the sound") == .mute)
    #expect(LevelParser.parse("unmute my mac") == .unmute)
    #expect(LevelParser.parse("unmute and turn it up") == .unmute)
}

@Test func unknownLevelIsNil() {
    #expect(LevelParser.parse("volume banana") == nil)
    #expect(LevelParser.parse("brightness") == nil)
}
