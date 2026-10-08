import Foundation
import Testing
@testable import Actions

@Test func searchURLPercentEncodesSymbols() {
    #expect(WebSearch.url(for: "c++ & rust?").absoluteString
        == "https://www.google.com/search?q=c%2B%2B%20%26%20rust%3F")
    #expect(WebSearch.url(for: "rust async tutorials").absoluteString
        == "https://www.google.com/search?q=rust%20async%20tutorials")
}

@Test func overridePathWinsWhenExecutable() {
    let fake = Fixtures.url("fake-claude.sh").path
    #expect(ClaudeLocator.locate(override: fake, shellLookup: { "/should/not/be/used" })?.path == fake)
}

@Test func overridePathThatDoesNotExistFindsNothing() {
    #expect(ClaudeLocator.locate(override: "/nope/claude", shellLookup: { "/bin/sh" }) == nil)
}

@Test func blankOverrideFallsBackToTheShellLookup() {
    #expect(ClaudeLocator.locate(override: "  ", knownLocations: [], shellLookup: { "/bin/sh\n" })?.path == "/bin/sh")
    #expect(ClaudeLocator.locate(override: nil, knownLocations: [], shellLookup: { nil }) == nil)
}

// A standard install location is used directly, without starting a login shell.
@Test func knownInstallLocationsAreCheckedBeforeTheShell() {
    let found = ClaudeLocator.locate(override: nil, knownLocations: ["/nonexistent/claude", "/bin/sh"],
                                     shellLookup: { Issue.record("the shell shouldn't run"); return nil })
    #expect(found?.path == "/bin/sh")
}

// A login shell that hangs can't freeze Relay: the lookup gives up after its timeout.
@Test func shellLookupGivesUpOnAHangingShell() {
    let start = ContinuousClock.now
    #expect(ClaudeLocator.run("/bin/sh", ["-c", "sleep 30"], timeout: .milliseconds(300)) == nil)
    #expect(ContinuousClock.now - start < .seconds(2))
}

// A startup file that leaves a background process holding the output open doesn't block the result.
@Test func shellLookupReturnsEvenIfABackgroundProcessKeepsTheOutputOpen() {
    let start = ContinuousClock.now
    #expect(ClaudeLocator.run("/bin/sh", ["-c", "sleep 30 & echo /usr/local/bin/claude"], timeout: .seconds(3))
        == "/usr/local/bin/claude")
    #expect(ContinuousClock.now - start < .seconds(2))
}
