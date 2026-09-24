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
    #expect(ClaudeLocator.locate(override: "  ", shellLookup: { "/bin/sh\n" })?.path == "/bin/sh")
    #expect(ClaudeLocator.locate(override: nil, shellLookup: { nil }) == nil)
}
