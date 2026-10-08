import AVFoundation

public enum CaptureError: Error, Equatable {
    case permissionDenied
    case notRecording
    case noInputDevice
}

@MainActor
public protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    /// Loudness of the latest audio buffer, 0…1; 0 when not recording.
    var level: Float { get }
    func start() throws
    /// Stops recording and returns the recorded audio file.
    func stop() throws -> URL
}

/// Records the default microphone to a temporary .caf file between `start()` and `stop()`.
@MainActor
public final class MicRecorder: AudioRecording {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private let meter = LevelMeter()

    public init() {}

    public var level: Float { meter.level }

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
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.writer(to: file, meter: meter))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? FileManager.default.removeItem(at: url) // don't leave an empty recording behind
            throw error
        }
        self.engine = engine
        self.file = file
    }

    public func stop() throws -> URL {
        guard let engine, let file else { throw CaptureError.notRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file.close() // flush everything to disk before anyone reads it
        meter.reset()
        self.engine = nil
        self.file = nil
        return file.url
    }

    /// Deletes recordings a crash or forced quit left in the temp folder (`relay-<UUID>.caf`).
    public nonisolated static func removeLeftoverRecordings(in folder: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix("relay-") && name.hasSuffix(".caf") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Built outside the main actor on purpose: the tap runs on an audio thread, and a closure
    /// created inside this @MainActor class would inherit main-actor isolation and trap at runtime.
    private nonisolated static func writer(to file: AVAudioFile, meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            try? file.write(from: buffer)
            if let channel = buffer.floatChannelData?[0] {
                meter.update(with: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
        }
    }
}
