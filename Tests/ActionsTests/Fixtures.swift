import Foundation

/// Locates files in Tests/ActionsTests/Fixtures relative to this source file.
enum Fixtures {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    }

    static func lines(_ name: String) throws -> [String] {
        try String(contentsOf: url(name), encoding: .utf8).split(separator: "\n").map(String.init)
    }
}
