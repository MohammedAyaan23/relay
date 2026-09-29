import Foundation

/// Checks run at most once a day. A last check in the future (clock set back) counts as due.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}

public struct ReleaseSummary: Equatable, Sendable {
    public let tag: String
    public let url: URL
    public let draft: Bool
    public let prerelease: Bool

    public init(tag: String, url: URL, draft: Bool, prerelease: Bool) {
        self.tag = tag
        self.url = url
        self.draft = draft
        self.prerelease = prerelease
    }
}

public protocol ReleaseFeed: Sendable {
    func latest() async throws -> ReleaseSummary
}

/// GitHub's "latest release" endpoint, without authentication. Sends nothing about the user.
public struct GitHubReleaseFeed: ReleaseFeed {
    public let repository: String

    public init(repository: String) {
        self.repository = repository
    }

    public func latest() async throws -> ReleaseSummary {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Relay", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data)
    }

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }

    public static func decode(_ data: Data) throws -> ReleaseSummary {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseSummary(tag: payload.tag_name, url: payload.html_url, draft: payload.draft, prerelease: payload.prerelease)
    }
}

public enum UpdateResult: Equatable, Sendable {
    case upToDate
    case available(version: String, url: URL)
    case failed
}

public enum UpdateChecker {
    /// Never throws or alerts: any problem is `.failed`, and the next scheduled check tries again.
    public static func check(current: String, feed: some ReleaseFeed) async -> UpdateResult {
        guard let mine = AppVersion(current), let latest = try? await feed.latest() else { return .failed }
        if latest.draft || latest.prerelease { return .upToDate }
        guard let theirs = AppVersion(latest.tag) else { return .failed }
        return theirs > mine ? .available(version: theirs.description, url: latest.url) : .upToDate
    }
}
