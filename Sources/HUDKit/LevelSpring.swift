/// Smooths the microphone level before it drives the goo. Mic readings arrive about 10 times a second and
/// jump between buffers; fed straight in, the blobs jumped up to ~17 points in one frame. A critically
/// damped spring is smooth in both value and speed, never overshoots, and reaches 90% in about 0.5 s.
public struct LevelSpring: Sendable {
    public private(set) var value: Double = 0
    private var velocity: Double = 0
    /// Stiffness in radians per second; 8 matched a steady level's smoothness in measurements.
    public let omega: Double

    public init(omega: Double = 8) {
        self.omega = omega
    }

    /// Advances the spring by `dt` seconds toward `target` (0…1) and returns the smoothed level.
    public mutating func step(toward target: Double, dt: Double) -> Double {
        // A long gap (the pill was hidden) is treated as one short frame, so it can't fling the level.
        let dt = min(max(dt, 0), 1.0 / 20)
        let substeps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(substeps)
        for _ in 0..<substeps {
            let acceleration = omega * omega * (target - value) - 2 * omega * velocity
            velocity += acceleration * h
            value += velocity * h
        }
        value = min(max(value, 0), 1)
        return value
    }

    public mutating func reset(to level: Double = 0) {
        value = level
        velocity = 0
    }
}
