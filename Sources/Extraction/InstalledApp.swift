import Foundation

public struct InstalledApp: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// Lists installed `.app` bundles.
public enum AppIndex {
    public static let defaultDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    /// `.app` bundles directly inside each directory (not recursive). Missing directories are skipped.
    public static func scan(_ directories: [URL] = defaultDirectories) -> [InstalledApp] {
        directories.flatMap { directory in
            let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return items
                .filter { $0.pathExtension == "app" }
                .map { InstalledApp(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
        }
    }
}
