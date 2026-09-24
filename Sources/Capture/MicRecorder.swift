import AVFoundation

public enum CaptureError: Error, Equatable {
    case permissionDenied
    case notRecording
    case noInputDevice
}

@MainActor
public protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    func start() throws
    /// Stops recording and returns the recorded audio file.
    func stop() throws -> URL
}

/// Records the default microphone to a temporary .caf file between `start()` and `stop()`.
@MainActor
public final class MicRecorder: AudioRecording {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?

    public init() {}

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw CaptureError.permissionDenied }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw CaptureError.noInputDevice }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.writer(to: file))
        try engine.start()
        self.engine = engine
        self.file = file
    }

    public func stop() throws -> URL {
        guard let engine, let file else { throw CaptureError.notRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file.close() // flush everything to disk before anyone reads it
        self.engine = nil
        self.file = nil
        return file.url
    }

    /// Built outside the main actor on purpose: the tap runs on an audio thread, and a closure
    /// created inside this @MainActor class would inherit main-actor isolation and trap at runtime.
    private nonisolated static func writer(to file: AVAudioFile) -> AVAudioNodeTapBlock {
        { buffer, _ in try? file.write(from: buffer) }
    }
}
