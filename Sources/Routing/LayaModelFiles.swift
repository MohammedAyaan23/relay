import CryptoKit
import Foundation

/// The Laya files Relay uses, pinned to one Hugging Face commit and checked by SHA-256 before loading.
/// (FluidUse's own downloader follows the changeable `main` branch and checks only sizes.)
public enum LayaModelFiles {
    public struct File: Sendable, Equatable {
        public let path: String
        public let sha256: String
    }

    public enum VerificationError: Error, LocalizedError {
        case mismatch(String)

        public var errorDescription: String? {
            switch self {
            case .mismatch(let path): "The downloaded Laya file \(path) isn't the expected version."
            }
        }
    }

    public static let repository = "FluidInference/laya-coreml"
    public static let revision = "7b8d7a2b7e28e746c6ecaad44bbcd5cf251a4fcc"
    /// The "e8" weights: fp16 encoder with an int8 embedding table, 30% smaller than fp16 with the same parity gates.
    static let precision = "e8"
    static let bundle = "laya_multilingual_e8_L128_options32.mlmodelc"
    public static let files = [
        File(path: "tokenizer.json", sha256: "609d8f4c067cd3950f88594c5a802616cea245823836ef5848ee4fc40aab5b6f"),
        File(path: "\(bundle)/analytics/coremldata.bin",
             sha256: "5cabcada4e3adc09e026c4b37a48d71e828bb3f80d12de0356b3369375ba1da6"),
        File(path: "\(bundle)/coremldata.bin", sha256: "4fb10774cd0860881220a37c80b416f465e3a9b5636f83c740647bafc14fbce5"),
        File(path: "\(bundle)/model.mil", sha256: "bcdb6102dacea9581875b3e8bc0f05e0b568d437bc20a8cf35b11f06edfa919a"),
        File(path: "\(bundle)/weights/weight.bin",
             sha256: "ca1e5da71f1498eac7b68722c9f5c3d43d1ce299aaf0c29743585749f3cc9677"),
    ]

    public typealias Fetch = @Sendable (URL) async throws -> URL
    public typealias Progress = @Sendable (_ file: String) -> Void

    /// Makes sure every file in `folder` matches its hash. A matching file is kept; a missing one is downloaded
    /// from the pinned commit; a changed one is set aside (renamed, never deleted) and downloaded again.
    /// A download that doesn't match its hash is thrown away and nothing is installed.
    public static func ensureVerified(in folder: URL, files: [File] = files, fetch: Fetch = download,
                                      progress: Progress? = nil) async throws {
        let manager = FileManager.default
        for file in files {
            let destination = folder.appendingPathComponent(file.path)
            if manager.fileExists(atPath: destination.path) {
                if try hash(of: destination) == file.sha256 { continue }
                let stamp = Int(Date().timeIntervalSince1970)
                try manager.moveItem(at: destination, to: destination.deletingLastPathComponent()
                    .appendingPathComponent("\(destination.lastPathComponent).mismatch-\(stamp)"))
            }
            progress?(file.path)
            let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
            let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(encoded)")!
            let temporary = try await fetch(url)
            defer { try? manager.removeItem(at: temporary) }
            guard try hash(of: temporary) == file.sha256 else { throw VerificationError.mismatch(file.path) }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: temporary, to: destination)
        }
    }

    /// Downloads over HTTPS to a temporary file.
    public static func download(_ url: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        // URLSession deletes its file when this returns, so move it somewhere we own.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("relay-laya-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporary, to: kept)
        return kept
    }

    /// SHA-256 of a file, read in 4 MB chunks so the ~450 MB weights never sit in memory at once.
    static func hash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
