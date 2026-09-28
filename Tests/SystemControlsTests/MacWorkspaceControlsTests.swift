import CoreGraphics
import Foundation
import Testing
@testable import SystemControls

@Test func windowShortcutsUseTheStandardKeys() {
    #expect(KeyEvents.shortcut(for: .minimize).key == 46)
    #expect(KeyEvents.shortcut(for: .minimize).flags == .maskCommand)
    #expect(KeyEvents.shortcut(for: .fullScreen).key == 3)
    #expect(KeyEvents.shortcut(for: .fullScreen).flags == [.maskControl, .maskCommand])
    #expect(KeyEvents.shortcut(for: .close).key == 13)
}

@Test func createsFoldersAndFilesWithoutOverwriting() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let controls = MacWorkspaceControls()

    let first = try await controls.createFolder(named: "invoices", in: folder)
    let second = try await controls.createFolder(named: "invoices", in: folder)
    #expect(first.lastPathComponent == "invoices")
    #expect(second.lastPathComponent == "invoices 2")

    let note = try await controls.createFile(named: "todo.txt", in: folder)
    try "keep me".write(to: note, atomically: true, encoding: .utf8)
    let another = try await controls.createFile(named: "todo.txt", in: folder)
    #expect(another.lastPathComponent == "todo 2.txt")
    #expect(try String(contentsOf: note, encoding: .utf8) == "keep me")
}

@Test func creatingInAMissingFolderFails() async {
    let missing = URL(fileURLWithPath: "/nonexistent-relay-folder")
    await #expect(throws: SystemControlError.self) {
        _ = try await MacWorkspaceControls().createFolder(named: "x", in: missing)
    }
}
