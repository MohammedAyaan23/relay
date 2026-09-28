import Testing
@testable import HUDKit

private let frame = 1.0 / 60

@Test func risesQuicklyWithoutOvershooting() {
    var spring = LevelSpring()
    var values: [Double] = []
    for _ in 0..<60 { values.append(spring.step(toward: 0.6, dt: frame)) }
    #expect(values[29] >= 0.53)                  // ~90% within half a second
    #expect(values.allSatisfy { $0 <= 0.6 * 1.01 }) // no bounce past the target
}

@Test func steppyMicLevelsBecomeSmoothMotion() {
    // Real mic levels arrive ~10 times a second and jump between readings.
    let readings = [0.0, 0.7, 0.1, 0.6, 0.0, 0.7, 0.2, 0.7, 0.0, 0.5, 0.7, 0.0]
    var spring = LevelSpring()
    var previous = 0.0
    var largestChange = 0.0
    for frameIndex in 0..<(readings.count * 5) {
        let value = spring.step(toward: readings[frameIndex / 5], dt: frame)
        largestChange = max(largestChange, abs(value - previous))
        previous = value
    }
    #expect(largestChange < 0.05) // the raw input jumps by up to 0.7 in one frame
}

@Test func longGapsDoNotOvershoot() {
    var spring = LevelSpring()
    let value = spring.step(toward: 0.5, dt: 2.0) // e.g. the pill was hidden for 2 s
    #expect(value >= 0 && value <= 0.5)
}

@Test func resetJumpsStraightToAValue() {
    var spring = LevelSpring()
    _ = spring.step(toward: 1, dt: frame)
    spring.reset()
    #expect(spring.value == 0)
    #expect(spring.step(toward: 0, dt: frame) == 0)
}
