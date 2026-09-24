import Foundation

/// Remembers the latest Claude session ID for each project folder, in a small JSON file.
public struct SessionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relay/sessions.json")
    }

    public func sessionID(for project: URL) -> String? {
        load()[key(project)]
    }

    public func setSessionID(_ id: String?, for project: URL) throws {
        var all = load()
        all[key(project)] = id
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
    }

    private func key(_ project: URL) -> String {
        project.standardizedFileURL.path
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
