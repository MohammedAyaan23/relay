import Foundation
import Testing
@testable import Extraction
@testable import SystemControls

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func uniqueNameNumbersClashesLikeFinder() throws {
    let folder = try temporaryFolder()
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("invoices"), withIntermediateDirectories: false)
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices 2")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("invoices 2"), withIntermediateDirectories: false)
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices 3")
}

@Test func uniqueNameKeepsTheExtension() throws {
    let folder = try temporaryFolder()
    FileManager.default.createFile(atPath: folder.appendingPathComponent("todo.txt").path, contents: Data())
    #expect(UniqueName.available(for: "todo.txt", in: folder).lastPathComponent == "todo 2.txt")
}

private let home = URL(fileURLWithPath: "/Users/test")

@Test func searchDropsLibraryHiddenAndAppContents() {
    let paths = ["/Users/test/Library/Caches/budget.db", "/Users/test/.config/budget", "/Users/test/Apps/Budget.app/Contents/budget",
                 "/Users/test/Documents/Budget.xlsx"]
    let ranked = FileSearch.rank(paths: paths, query: "budget", home: home) { _ in nil }
    #expect(ranked.map(\.name) == ["Budget.xlsx"])
}

@Test func searchRanksExactThenPrefixThenContainsThenRecency() {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let paths = ["/Users/test/a/my budget notes.txt", "/Users/test/b/budget 2025.xlsx",
                 "/Users/test/c/budget 2026.xlsx", "/Users/test/d/Budget.pdf"]
    let ranked = FileSearch.rank(paths: paths, query: "budget", home: home) { url in
        url.path.contains("2026") ? new : old
    }
    #expect(ranked.map(\.name) == ["Budget.pdf", "budget 2026.xlsx", "budget 2025.xlsx", "my budget notes.txt"])
}

@Test func searchKeepsAtMostEight() {
    let paths = (1...20).map { "/Users/test/Documents/tax \($0).pdf" }
    #expect(FileSearch.rank(paths: paths, query: "tax", home: home) { _ in nil }.count == 8)
}

private let shot = URL(fileURLWithPath: "/Users/test/Desktop/Screenshot.png")

@Test(arguments: [
    (ScreenshotOptions(target: .screen, toClipboard: false, openAfter: false), ["-x", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .window, toClipboard: false, openAfter: false), ["-x", "-l", "42", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .area, toClipboard: false, openAfter: false), ["-x", "-i", "-s", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false), ["-x", "-c"]),
    (ScreenshotOptions(target: .window, toClipboard: true, openAfter: false), ["-x", "-c", "-l", "42"]),
    (ScreenshotOptions(target: .area, toClipboard: true, openAfter: false), ["-x", "-c", "-i", "-s"]),
])
func screenshotArguments(_ options: ScreenshotOptions, _ expected: [String]) {
    #expect(ScreenshotCommand.arguments(for: options, file: options.toClipboard ? nil : shot, windowID: 42) == expected)
}

@Test func areaScreenshotsGetLongerTimeout() {
    #expect(ScreenshotCommand.timeout(for: ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)) == .seconds(60))
    #expect(ScreenshotCommand.timeout(for: ScreenshotOptions(target: .window, toClipboard: false, openAfter: false)) == .seconds(15))
}

@Test func frontWindowIsTheFirstNormalWindowOfTheApp() {
    let windows: [[String: Any]] = [
        ["kCGWindowOwnerPID": 7, "kCGWindowLayer": 25, "kCGWindowOwnerName": "Control Centre", "kCGWindowNumber": 1],
        ["kCGWindowOwnerPID": 9, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Relay", "kCGWindowNumber": 2],
        ["kCGWindowOwnerPID": 42, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Safari", "kCGWindowNumber": 3],
        ["kCGWindowOwnerPID": 42, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Safari", "kCGWindowNumber": 4],
    ]
    #expect(WindowList.frontWindowID(pid: 42, windows: windows) == 3)
    #expect(WindowList.frontWindowID(pid: 9, windows: windows) == nil)
    #expect(WindowList.frontWindowID(pid: 5, windows: windows) == nil)
}

// MARK: Final-review findings

@Test func searchIncludesICloudDriveAndCloudStorage() {
    let paths = ["/Users/test/Library/Mobile Documents/com~apple~CloudDocs/8th sem grade card.pdf",
                 "/Users/test/Library/CloudStorage/Dropbox/grade card scan.png",
                 "/Users/test/Library/Caches/grade card.tmp"]
    let ranked = FileSearch.rank(paths: paths, query: "grade card", home: home) { _ in nil }
    #expect(Set(ranked.map(\.name)) == ["8th sem grade card.pdf", "grade card scan.png"])
}

@Test func pathCapAppliesAfterFiltering() {
    let libraryNoise = (1...400).map { "/Users/test/Library/Caches/doc \($0).tmp" }
    let ranked = FileSearch.rank(paths: libraryNoise + ["/Users/test/Documents/doc.txt"], query: "doc", home: home) { _ in nil }
    #expect(ranked.map(\.name) == ["doc.txt"])
}

private let areaShot = ScreenshotOptions.Target.area

@Test func screenshotResultsAreInterpreted() throws {
    let file = URL(fileURLWithPath: "/Users/test/Desktop/Screenshot.png")
    #expect(try ScreenshotCommand.interpret(status: 0, stderr: "", file: file, fileExists: true, target: .screen) == .saved(file))
    #expect(try ScreenshotCommand.interpret(status: 0, stderr: "", file: file, fileExists: false, target: .area) == .cancelled)
    #expect(try ScreenshotCommand.interpret(status: 1, stderr: "", file: file, fileExists: false, target: areaShot) == .cancelled)
    #expect(try ScreenshotCommand.interpret(status: 0, stderr: "", file: nil, fileExists: false, target: .window) == .copied)
    #expect(throws: SystemControlError.failed("screencapture exited 1")) {
        _ = try ScreenshotCommand.interpret(status: 1, stderr: "", file: file, fileExists: false, target: .screen)
    }
}

@Test func finderFolderScriptResultsAreInterpreted() throws {
    let ok = CommandResult(status: 0, stdout: "/Users/test/Projects/\n", stderr: "")
    #expect(try FinderFolderScript.interpret(ok)?.path == "/Users/test/Projects")
    #expect(try FinderFolderScript.interpret(CommandResult(status: 0, stdout: "missing value\n", stderr: "")) == nil)
    #expect(try FinderFolderScript.interpret(CommandResult(status: 0, stdout: "", stderr: "")) == nil)
    #expect(try FinderFolderScript.interpret(CommandResult(status: 1, stdout: "", stderr: "execution error: Finder got an error (-1712)")) == nil)
    #expect(throws: SystemControlError.automationDenied) {
        _ = try FinderFolderScript.interpret(CommandResult(status: 1, stdout: "", stderr: "Not authorized to send Apple events to Finder. (-1743)"))
    }
}
