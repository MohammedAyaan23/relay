import CoreGraphics
import Foundation

public struct Blob: Equatable, Sendable {
    public var center: CGPoint
    public var radius: CGFloat

    public init(center: CGPoint, radius: CGFloat) {
        self.center = center
        self.radius = radius
    }
}

/// What the goo is doing. Voice level is passed separately because it changes every frame.
public enum GooMode: CaseIterable, Sendable, Equatable {
    case idle, listening, thinking, result
}

/// Where the goo's blobs are at a moment in time. Pure maths, so the animation can be unit-tested;
/// the HUD draws these as metaballs (blur + alpha threshold) so touching blobs melt together.
public struct GooLayout: Sendable {
    public static let blobCount = 5
    private static let speeds: [Double] = [1.0, 1.3, 0.7, 1.6, 1.1]

    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    /// `level` is the microphone loudness 0…1; `reduceMotion` freezes time so nothing drifts.
    public func blobs(mode: GooMode, level: Double, time: TimeInterval, reduceMotion: Bool) -> [Blob] {
        let t = reduceMotion ? 0 : time
        let level = min(1, max(0, level))
        let w = Double(size.width), h = Double(size.height)
        let mid = CGPoint(x: w / 2, y: h / 2)
        let short = min(w, h)

        return (0..<Self.blobCount).map { i in
            let index = Double(i)
            let speed = Self.speeds[i]
            let blob: Blob
            switch mode {
            case .idle:
                blob = Blob(center: mid, radius: short * 0.18 * (1 + 0.06 * sin(t * 2)))

            case .listening:
                // Lava-lamp drift: louder speech swells the blobs and pushes them apart.
                let radius = h * 0.20 * (0.75 + 0.75 * level) * (1 + 0.15 * sin(t * 1.7 + index * 1.3))
                let spread = w * (0.10 + 0.25 * level)
                let lift = h * 0.15 * (0.5 + level)
                blob = Blob(center: CGPoint(x: w / 2 + spread * sin(t * 0.9 * speed + index * 1.25),
                                            y: h / 2 + lift * sin(t * 1.4 * speed + index * 0.9)),
                            radius: radius)

            case .thinking:
                // Blobs chase each other round an ellipse, merging as they pass.
                let angle = t * 3.2 + index * 2 * .pi / Double(Self.blobCount)
                let orbit = h * 0.22
                blob = Blob(center: CGPoint(x: w / 2 + orbit * 1.8 * cos(angle), y: h / 2 + orbit * sin(angle)),
                            radius: h * 0.17 * (1 + 0.1 * sin(t * 4 + index)))

            case .result:
                blob = Blob(center: mid, radius: short * 0.36)
            }
            return clamped(blob)
        }
    }

    /// Straight-line blend between two layouts, `progress` 0…1 (callers apply their own easing).
    public static func blend(from: [Blob], to: [Blob], progress: Double) -> [Blob] {
        guard from.count == to.count else { return to }
        let p = CGFloat(min(1, max(0, progress)))
        return zip(from, to).map { a, b in
            Blob(center: CGPoint(x: a.center.x + (b.center.x - a.center.x) * p,
                                 y: a.center.y + (b.center.y - a.center.y) * p),
                 radius: a.radius + (b.radius - a.radius) * p)
        }
    }

    private func clamped(_ blob: Blob) -> Blob {
        let radius = min(blob.radius, min(size.width, size.height) / 2)
        return Blob(center: CGPoint(x: min(max(blob.center.x, radius), size.width - radius),
                                    y: min(max(blob.center.y, radius), size.height - radius)),
                    radius: radius)
    }
}
