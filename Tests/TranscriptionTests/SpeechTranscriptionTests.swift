import Foundation
import Testing
@testable import Transcription

/// Uses Apple's on-device speech model. Run with `make test-speech`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RELAY_SPEECH_TESTS"] == "1"))
func transcribesASpokenCommand() async throws {
    let wav = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).wav")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-o", wav.path, "--data-format=LEI16@16000", "open safari"]
    try say.run()
    say.waitUntilExit()

    let transcriber = SpeechTranscription(requestAuthorization: false)
    try await transcriber.prepare()
    let text = try await transcriber.transcribe(wav)
    #expect(text.lowercased().contains("safari"))
}

@Test func transcribingBeforePrepareFails() async {
    let transcriber = SpeechTranscription(requestAuthorization: false)
    await #expect(throws: TranscriptionError.notPrepared) {
        _ = try await transcriber.transcribe(URL(fileURLWithPath: "/tmp/none.wav"))
    }
}
