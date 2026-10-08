import Foundation
import Testing
@testable import Capture

// Recordings left by a crash are removed at launch; nothing else in the folder is touched.
@Test func leftoverRecordingsAreRemovedAndOtherFilesKept() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["relay-1234.caf", "relay-abcd.caf", "other.caf", "relay-notes.txt"] {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
    }
    MicRecorder.removeLeftoverRecordings(in: folder)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["other.caf", "relay-notes.txt"])
}
