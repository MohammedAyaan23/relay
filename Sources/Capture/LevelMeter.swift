import Foundation
import Synchronization

/// Loudness of the latest microphone buffer: written on the audio thread, read on the main thread.
public final class LevelMeter: Sendable {
    private let value = Mutex<Float>(0)

    public init() {}

    /// 0 (silence) … 1 (full scale).
    public var level: Float { value.withLock { $0 } }

    func update(with samples: UnsafeBufferPointer<Float>) {
        let level = Self.normalizedLevel(of: samples)
        value.withLock { $0 = level }
    }

    func reset() {
        value.withLock { $0 = 0 }
    }

    /// RMS loudness mapped from -50 dB…0 dB onto 0…1, so room noise reads as 0 and speech fills the range.
    static func normalizedLevel(of samples: some Collection<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(meanSquare)
        return min(1, max(0, (decibels + 50) / 50))
    }
}
