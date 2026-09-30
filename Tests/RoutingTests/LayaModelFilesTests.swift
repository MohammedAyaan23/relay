import CryptoKit
import Foundation
import Testing
@testable import Routing

private func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private let manifest = [
    LayaModelFiles.File(path: "tokenizer.json", sha256: sha256("tokens")),
    LayaModelFiles.File(path: "model.mlmodelc/weights/weight.bin", sha256: sha256("weights")),
]

/// Serves fixed contents per file name, recording which paths were fetched.
private final class FakeServer: @unchecked Sendable {
    var contents: [String: String]
    private(set) var fetched: [String] = []
    init(_ contents: [String: String]) { self.contents = contents }

    func fetch(_ url: URL) async throws -> URL {
        let path = url.path.components(separatedBy: "/resolve/\(LayaModelFiles.revision)/").last ?? ""
        fetched.append(path)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("relay-dl-\(UUID().uuidString)")
        try Data((contents[path] ?? "").utf8).write(to: file)
        return file
    }
}

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ path: String, in folder: URL) throws {
    let url = folder.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@Test func downloadsFromThePinnedRevisionAndChecksHashes() async throws {
    let folder = try tempFolder()
    let server = FakeServer(["tokenizer.json": "tokens", "model.mlmodelc/weights/weight.bin": "weights"])
    try await LayaModelFiles.ensureVerified(in: folder, files: manifest, fetch: server.fetch)
    #expect(server.fetched == ["tokenizer.json", "model.mlmodelc/weights/weight.bin"])
    #expect(try String(contentsOf: folder.appendingPathComponent("tokenizer.json"), encoding: .utf8) == "tokens")
}

@Test func matchingFilesAreKeptWithoutDownloading() async throws {
    let folder = try tempFolder()
    try write("tokens", "tokenizer.json", in: folder)
    try write("weights", "model.mlmodelc/weights/weight.bin", in: folder)
    let server = FakeServer([:])
    try await LayaModelFiles.ensureVerified(in: folder, files: manifest, fetch: server.fetch)
    #expect(server.fetched.isEmpty)
}

@Test func aTamperedDownloadIsRejectedAndNotInstalled() async throws {
    let folder = try tempFolder()
    let server = FakeServer(["tokenizer.json": "evil tokens", "model.mlmodelc/weights/weight.bin": "weights"])
    await #expect(throws: LayaModelFiles.VerificationError.self) {
        try await LayaModelFiles.ensureVerified(in: folder, files: manifest, fetch: server.fetch)
    }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path))
}

@Test func aChangedLocalFileIsSetAsideAndDownloadedAgain() async throws {
    let folder = try tempFolder()
    try write("changed", "tokenizer.json", in: folder)
    try write("weights", "model.mlmodelc/weights/weight.bin", in: folder)
    let server = FakeServer(["tokenizer.json": "tokens"])
    try await LayaModelFiles.ensureVerified(in: folder, files: manifest, fetch: server.fetch)
    #expect(server.fetched == ["tokenizer.json"])
    #expect(try String(contentsOf: folder.appendingPathComponent("tokenizer.json"), encoding: .utf8) == "tokens")
    let setAside = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("tokenizer.json.mismatch") }
    #expect(setAside.count == 1) // moved aside, not deleted
}

@Test func theRealManifestPinsACommitAndEveryFileHasAHash() {
    #expect(LayaModelFiles.revision.count == 40)
    #expect(LayaModelFiles.files.count == 5)
    #expect(LayaModelFiles.files.allSatisfy { $0.sha256.count == 64 })
}
