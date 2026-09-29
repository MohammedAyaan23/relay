import Foundation
import Testing
@testable import AppSupport

private struct FakeFeed: ReleaseFeed {
    var result: Result<ReleaseSummary, URLError>
    func latest() async throws -> ReleaseSummary { try result.get() }
}

private let page = URL(string: "https://github.com/me/relay/releases/tag/v0.2.0")!

private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> FakeFeed {
    FakeFeed(result: .success(ReleaseSummary(tag: tag, url: page, draft: draft, prerelease: prerelease)))
}

@Test func scheduleIsDueWithoutALastCheck() {
    #expect(UpdateSchedule.isDue(lastCheck: nil, now: .now))
}

@Test func scheduleWaits24Hours() {
    let now = Date()
    #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
    #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
}

@Test func futureLastCheckIsDue() {
    let now = Date()
    #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
}

@Test func newerReleaseIsAvailable() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0")) == .available(version: "0.2.0", url: page))
}

@Test func sameOrOlderIsUpToDate() async {
    #expect(await UpdateChecker.check(current: "0.2.0", feed: release("v0.2.0")) == .upToDate)
    #expect(await UpdateChecker.check(current: "0.10.0", feed: release("v0.9.9")) == .upToDate)
}

@Test func draftsAndPrereleasesAreIgnored() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0", draft: true)) == .upToDate)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0", prerelease: true)) == .upToDate)
}

@Test func junkTagOrErrorFails() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("nightly")) == .failed)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: FakeFeed(result: .failure(URLError(.notConnectedToInternet)))) == .failed)
    #expect(await UpdateChecker.check(current: "dev", feed: release("v0.2.0")) == .failed)
}

@Test func decodesGitHubReleaseJSON() throws {
    let json = """
    {"url":"https://api.github.com/repos/me/relay/releases/1","html_url":"https://github.com/me/relay/releases/tag/v0.2.0",
     "id":1,"tag_name":"v0.2.0","name":"Relay 0.2.0","draft":false,"prerelease":false,
     "assets":[{"name":"Relay-0.2.0.dmg","size":123}],"body":"Notes"}
    """
    let summary = try GitHubReleaseFeed.decode(Data(json.utf8))
    #expect(summary == ReleaseSummary(tag: "v0.2.0", url: page, draft: false, prerelease: false))
}

@Test func badJSONThrows() {
    #expect(throws: (any Error).self) { try GitHubReleaseFeed.decode(Data("{\"message\":\"Not Found\"}".utf8)) }
}

@Test func malformedRepositoryFailsQuietly() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: GitHubReleaseFeed(repository: "not a repo")) == .failed)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: GitHubReleaseFeed(repository: "/relay")) == .failed)
}
