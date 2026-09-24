import AVFoundation
import Speech

public enum TranscriptionError: Error, Equatable {
    case permissionDenied
    case localeUnsupported
    case notPrepared
}

public protocol Transcribing: Sendable {
    /// Asks for speech permission if needed and installs the on-device speech model.
    func prepare() async throws
    func transcribe(_ audio: URL) async throws -> String
}

/// On-device speech-to-text with Apple's SpeechAnalyzer (macOS 26).
public actor SpeechTranscription: Transcribing {
    private let requestAuthorization: Bool
    private var locale: Locale?

    /// `requestAuthorization: false` is for tests run from a terminal, which can't show the prompt.
    public init(requestAuthorization: Bool = true) {
        self.requestAuthorization = requestAuthorization
    }

    public func prepare() async throws {
        if requestAuthorization {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { throw TranscriptionError.permissionDenied }
        }
        var supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        if supported == nil {
            supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        }
        guard let supported else { throw TranscriptionError.localeUnsupported }
        let probe = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
        locale = supported
    }

    public func transcribe(_ audio: URL) async throws -> String {
        guard let locale else { throw TranscriptionError.notPrepared }
        // SpeechAnalyzer sessions are single-use, so each call builds a fresh pipeline.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var text = ""
            for try await result in transcriber.results { text += String(result.text.characters) }
            return text
        }
        let file = try AVAudioFile(forReading: audio)
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
