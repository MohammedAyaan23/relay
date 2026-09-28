import AppKit
import Extraction
import Foundation

/// The real implementation: NSWorkspace, key events, Finder AppleScript, `mdfind` and `screencapture`.
public final class MacWorkspaceControls: WorkspaceControlling {
    private let runner: any CommandRunning
    private let areaRunner: any CommandRunning

    public init(runner: any CommandRunning = ProcessRunner(),
                areaRunner: any CommandRunning = ProcessRunner(timeout: .seconds(60))) {
        self.runner = runner
        self.areaRunner = areaRunner
    }

    // MARK: Apps and windows

    @MainActor private static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    @MainActor private static func frontmostApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app
    }

    public func runningApps() async -> [InstalledApp] {
        await MainActor.run {
            Self.regularApps().compactMap { app in
                guard let name = app.localizedName, let url = app.bundleURL else { return nil }
                return InstalledApp(name: name, url: url)
            }
        }
    }

    public func frontmostAppName() async -> String? {
        await MainActor.run { Self.frontmostApp()?.localizedName }
    }

    public func quit(appNamed name: String) async throws {
        try await MainActor.run {
            guard let app = Self.regularApps().first(where: { $0.localizedName == name }) else {
                throw SystemControlError.appNotRunning(name)
            }
            _ = app.terminate() // a normal Quit; never forceTerminate()
        }
    }

    public func hide(appNamed name: String) async throws {
        try await MainActor.run {
            guard let app = Self.regularApps().first(where: { $0.localizedName == name }) else {
                throw SystemControlError.appNotRunning(name)
            }
            _ = app.hide()
        }
    }

    public func sendWindowShortcut(_ shortcut: WindowShortcut) async throws {
        try Permissions.requireAccessibility()
        try await MainActor.run {
            guard Self.frontmostApp() != nil else { throw SystemControlError.noFrontWindow }
            KeyEvents.press(shortcut)
        }
    }

    // MARK: Files

    public func frontFinderFolder() async throws -> URL? {
        try await MainActor.run {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return nil }
            let source = "tell application \"Finder\" to if (count of Finder windows) > 0 then "
                + "POSIX path of (target of front Finder window as alias)"
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                if error[NSAppleScript.errorNumber] as? Int == -1743 { throw SystemControlError.automationDenied }
                return nil
            }
            guard let path = result?.stringValue, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    public func createFolder(named name: String, in folder: URL) async throws -> URL {
        try Self.requireFolder(folder)
        let url = UniqueName.available(for: name, in: folder)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw SystemControlError.failed(error.localizedDescription)
        }
        return url
    }

    public func createFile(named name: String, in folder: URL) async throws -> URL {
        try Self.requireFolder(folder)
        let url = UniqueName.available(for: name, in: folder)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw SystemControlError.failed("couldn't write in \(folder.lastPathComponent)")
        }
        return url
    }

    private static func requireFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SystemControlError.failed("the folder \(folder.path) doesn't exist")
        }
    }

    public func searchFiles(_ query: String) async throws -> [FileMatch] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result: CommandResult
        do {
            result = try await runner.run("/usr/bin/mdfind", ["-onlyin", home.path, "-name", query])
        } catch {
            throw SystemControlError.searchFailed(error.localizedDescription)
        }
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.searchFailed(reason.isEmpty ? "mdfind exited \(result.status)" : reason)
        }
        let paths = result.stdout.split(separator: "\n").prefix(FileSearch.pathLimit).map(String.init)
        return FileSearch.rank(paths: paths, query: query, home: home) { url in
            try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        }
    }

    public func open(_ url: URL) async throws {
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    public func reveal(_ url: URL) async throws {
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Screenshots

    public func captureScreenshot(_ options: ScreenshotOptions) async throws -> ScreenshotResult {
        try Permissions.requireScreenRecording()
        var windowID: Int?
        if options.target == .window {
            windowID = await MainActor.run { () -> Int? in
                guard let app = Self.frontmostApp() else { return nil }
                let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]] ?? []
                return WindowList.frontWindowID(pid: app.processIdentifier, windows: list)
            }
            guard windowID != nil else { throw SystemControlError.noFrontWindow }
        }
        let file: URL? = options.toClipboard ? nil : ScreenshotLocation.folder(
            defaultsValue: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser
        ).appendingPathComponent(ScreenshotLocation.fileName(for: Date()))

        let arguments = ScreenshotCommand.arguments(for: options, file: file, windowID: windowID)
        let result = try await (options.target == .area ? areaRunner : runner).run("/usr/sbin/screencapture", arguments)
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "screencapture exited \(result.status)" : reason)
        }
        guard let file else { return .copied }
        return FileManager.default.fileExists(atPath: file.path) ? .saved(file) : .cancelled
    }
}
