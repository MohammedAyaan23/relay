import Foundation
import Testing
@testable import Extraction
@testable import SystemControls

@Test func targetLevels() {
    #expect(KeyboardLightPlan.target(for: .set(30), current: 0.8) == 0.3)
    #expect(abs(KeyboardLightPlan.target(for: .up(10), current: 0.5) - 0.6) < 0.0001)
    #expect(KeyboardLightPlan.target(for: .up(10), current: 0.95) == 1)
    #expect(KeyboardLightPlan.target(for: .down(6), current: 0.03) == 0)
    #expect(KeyboardLightPlan.target(for: .mute, current: 0.4) == 0)
    #expect(KeyboardLightPlan.target(for: .unmute, current: 0) == 0.5)
}

@Test func fallbackKeyPresses() {
    #expect(KeyboardLightPlan.presses(for: .set(30)) == KeyboardLightPlan.Presses(down: 16, up: 5))
    #expect(KeyboardLightPlan.presses(for: .set(100)) == KeyboardLightPlan.Presses(down: 16, up: 16))
    #expect(KeyboardLightPlan.presses(for: .mute) == KeyboardLightPlan.Presses(down: 16, up: 0))
    #expect(KeyboardLightPlan.presses(for: .unmute) == KeyboardLightPlan.Presses(down: 16, up: 8))
    #expect(KeyboardLightPlan.presses(for: .up(10)) == KeyboardLightPlan.Presses(down: 0, up: 2))
    #expect(KeyboardLightPlan.presses(for: .down(6)) == KeyboardLightPlan.Presses(down: 1, up: 0))
}

@Test func fallbackResultingPercent() {
    #expect(KeyboardLightPlan.resultingPercent(for: .set(30)) == 31)
    #expect(KeyboardLightPlan.resultingPercent(for: .set(0)) == 0)
    #expect(KeyboardLightPlan.resultingPercent(for: .unmute) == 50)
    #expect(KeyboardLightPlan.resultingPercent(for: .up(10)) == nil)
}

@Test func keyboardIlluminationKeyCodes() {
    #expect(KeyEvents.illuminationUp == 21)
    #expect(KeyEvents.illuminationDown == 22)
}

/// Reads (never changes) the real backlight. Run with RELAY_SYSTEM_TESTS=1 make test FILTER=KeyboardLightPlanTests.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RELAY_SYSTEM_TESTS"] == "1"))
func readsTheRealKeyboardBacklight() throws {
    let backlight = try #require(KeyboardBacklight.make())
    #expect((0...1).contains(backlight.level()))
}
