import Extraction
import Foundation

public enum WindowShortcut: Sendable, Equatable {
    case minimize   // ⌘M
    case fullScreen // ⌃⌘F
    case close      // ⌘W
}

public enum ScreenshotResult: Sendable, Equatable {
    case saved(URL)
    case copied
    case cancelled
}

public struct FileMatch: Sendable, Equatable, Hashable {
    public let name: String
    public let url: URL
    public let lastUsed: Date?

    public init(name: String, url: URL, lastUsed: Date?) {
        self.name = name
        self.url = url
        self.lastUsed = lastUsed
    }
}

/// Apps, windows, files and screenshots. A protocol so the assistant can be tested with a fake.
public protocol WorkspaceControlling: Sendable {
    /// Regular (Dock) apps that are running, excluding Relay.
    func runningApps() async -> [InstalledApp]
    /// The app in front, or nil when Relay itself is in front.
    func frontmostAppName() async -> String?
    /// A normal Quit: apps may still ask to save.
    func quit(appNamed name: String) async throws
    func hide(appNamed name: String) async throws
    /// Sends ⌘M / ⌃⌘F / ⌘W to the app in front.
    func sendWindowShortcut(_ shortcut: WindowShortcut) async throws
    /// The folder of the front Finder window, or nil unless Finder is in front with a window.
    func frontFinderFolder() async throws -> URL?
    func createFolder(named name: String, in folder: URL) async throws -> URL
    func createFile(named name: String, in folder: URL) async throws -> URL
    /// Files in the home folder whose names match, best first, at most 8.
    func searchFiles(_ query: String) async throws -> [FileMatch]
    func open(_ url: URL) async throws
    func reveal(_ url: URL) async throws
    func captureScreenshot(_ options: ScreenshotOptions) async throws -> ScreenshotResult
}
