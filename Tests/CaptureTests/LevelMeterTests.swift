import Foundation
import Testing
@testable import Capture

@Test func silenceIsZero() {
    #expect(LevelMeter.normalizedLevel(of: [Float](repeating: 0, count: 512)) == 0)
    #expect(LevelMeter.normalizedLevel(of: [Float]()) == 0)
}

@Test func fullScaleSpeechIsNearlyOne() {
    let sine = (0..<512).map { Float(sin(Double($0) * 0.1)) }
    #expect(LevelMeter.normalizedLevel(of: sine) > 0.9)
}

@Test func quietRoomNoiseIsClampedToZero() {
    #expect(LevelMeter.normalizedLevel(of: [Float](repeating: 0.001, count: 512)) == 0) // -60 dB
}

@Test func levelRisesWithLoudness() {
    let soft = LevelMeter.normalizedLevel(of: [Float](repeating: 0.01, count: 512)) // -40 dB
    let loud = LevelMeter.normalizedLevel(of: [Float](repeating: 0.1, count: 512))  // -20 dB
    #expect(abs(soft - 0.2) < 0.01)
    #expect(abs(loud - 0.6) < 0.01)
}
