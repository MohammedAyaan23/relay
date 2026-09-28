import Testing
@testable import Routing

@Test(arguments: [
    ("turn the volume up", RoutedIntent.volume),
    ("set volume to 40 percent", .volume),
    ("it's too loud, bring it down a bit", .volume),
    ("mute the sound", .volume),
    ("make the screen brighter", .brightness),
    ("dim the display", .brightness),
    ("switch to dark mode", .darkMode),
    ("turn on light mode", .darkMode),
    ("turn on do not disturb", .focus),
    ("i need to focus, silence notifications", .focus),
    ("lock my mac", .lock),
    ("take a screenshot", .screenshot),
    ("grab a screen capture", .screenshot),
    ("play some music", .mediaPlayPause),
    ("pause", .mediaPlayPause),
    ("stop the music", .mediaPlayPause),
    ("resume the song", .mediaPlayPause),
    ("next song", .mediaNext),
    ("skip this track", .mediaNext),
    ("go back to the previous song", .mediaPrevious),
    ("play that last track again", .mediaPrevious),
])
func deviceCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("crank up the volume", RoutedIntent.volume),
    ("lower the sound", .volume),
    ("unmute my mac", .volume),
    ("turn the brightness all the way up", .brightness),
    ("the screen is too bright", .brightness),
    ("turn dark mode off", .darkMode),
    ("enable do not disturb for an hour", .focus),
    ("lock this computer", .lock),
    ("screenshot the screen", .screenshot),
    ("hit play", .mediaPlayPause),
    ("pause the song please", .mediaPlayPause),
    ("skip to the next one", .mediaNext),
    ("previous song please", .mediaPrevious),
])
func heldOutDevicePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    "search for sound effects",
    "google how loud is a jet engine",
    "tell claude to mute the tests",
    "my brother is visiting next week",
    "unlock the door",
    "open the music app",
    "i think it's going to rain",
])
func otherCommandsAreLeftToLaya(_ transcript: String) {
    #expect(CommandRules.match(transcript) == nil)
}

// MARK: Final-review findings

@Test(arguments: ["it's too quiet", "i can't hear anything"])
func tooQuietIsAVolumeCommand(_ transcript: String) {
    #expect(CommandRules.match(transcript) == .volume)
}

@Test(arguments: [
    "show my notifications",
    "clear my notifications",
    "open lock screen settings",
    "how do i pick a lock",
    "open sound settings",
    "next week's weather",
    "what was the previous song called",
])
func everydayPhrasesDoNotTriggerDeviceActions(_ transcript: String) {
    #expect(CommandRules.match(transcript) == nil)
}
