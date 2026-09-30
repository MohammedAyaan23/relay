import Foundation
import Testing
@testable import SystemControls

@Test func appsScriptsAndLinksCanRunCode() {
    for name in ["Evil.app", "setup.command", "run.sh", "tool.py", "go.terminal", "x.webloc", "x.inetloc",
                 "x.fileloc", "install.pkg", "flow.workflow", "a.shortcut", "s.scpt", "s.applescript", "X.prefPane",
                 "UPPER.APP"] {
        #expect(LaunchableFile.mightRunCode(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
    }
}

@Test func documentsDontRunCode() {
    for name in ["Budget 2026.xlsx", "lease.pdf", "notes.txt", "photo.jpg", "Report.docx", "missing-file"] {
        #expect(!LaunchableFile.mightRunCode(URL(fileURLWithPath: "/tmp/relay-none/\(name)")), "\(name)")
    }
}

@Test func executableFileWithoutExtensionRunsCodeButAFolderDoesNot() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let tool = dir.appendingPathComponent("tool")
    FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8),
                                   attributes: [.posixPermissions: 0o755])
    let folder = dir.appendingPathComponent("Projects")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    #expect(LaunchableFile.mightRunCode(tool))
    #expect(!LaunchableFile.mightRunCode(folder))
}
