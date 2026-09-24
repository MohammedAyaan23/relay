import Foundation
import Testing
@testable import Extraction

private func app(_ name: String) -> InstalledApp {
    InstalledApp(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
}

private let apps = [app("Safari"), app("Spotify"), app("Xcode"), app("Visual Studio Code"), app("Notes")]

@Test func findsAppNamedInsideTheSentence() {
    #expect(AppMatcher(apps: apps).match("can you fire up Spotify") == .found(app("Spotify")))
}

@Test func prefersTheLongestMatchingName() {
    let withCode = apps + [app("Code")]
    #expect(AppMatcher(apps: withCode).match("open visual studio code") == .found(app("Visual Studio Code")))
}

@Test func fuzzyMatchesSmallMishearings() {
    #expect(AppMatcher(apps: apps).match("open spotfy") == .found(app("Spotify")))
    #expect(AppMatcher(apps: apps).match("launch x code") == .found(app("Xcode")))
}

@Test func reportsClosestAppsWhenNothingMatches() {
    guard case .notFound(let query, let suggestions) = AppMatcher(apps: apps).match("open photoshop") else {
        Issue.record("expected notFound"); return
    }
    #expect(query == "photoshop")
    #expect(suggestions.count == 3)
}

@Test func emptyRequestIsNotFoundWithEmptyQuery() {
    #expect(AppMatcher(apps: apps).match("open") == .notFound(query: "", suggestions: []))
}

@Test func scanListsAppBundlesAndSkipsMissingFolders() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("Foo.app"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("NotAnApp"), withIntermediateDirectories: true)
    let found = AppIndex.scan([dir, dir.appendingPathComponent("missing")])
    #expect(found.map(\.name) == ["Foo"])
}
