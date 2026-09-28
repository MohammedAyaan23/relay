import Foundation
import Testing
@testable import Extraction
@testable import SystemControls

@Test func appearanceScriptForEachMode() {
    #expect(AppearanceScript.source(for: .on)
        == "tell application \"System Events\" to tell appearance preferences to set dark mode to true")
    #expect(AppearanceScript.source(for: .off).hasSuffix("set dark mode to false"))
    #expect(AppearanceScript.source(for: .toggle).hasSuffix("set dark mode to not dark mode"))
}

@Test func mediaKeysUseTheSystemKeyCodes() {
    #expect(KeyEvents.code(for: .playPause) == 16)
    #expect(KeyEvents.code(for: .next) == 17)
    #expect(KeyEvents.code(for: .previous) == 18)
}

@Test func brightnessPercentBecomesAFraction() {
    #expect(MacSystemControls.brightnessInput(percent: 70) == "0.70")
    #expect(MacSystemControls.brightnessInput(percent: 5) == "0.05")
    #expect(MacSystemControls.brightnessInput(percent: 100) == "1.00")
}

/// Reads (never changes) the real output volume. Run with RELAY_SYSTEM_TESTS=1 make test FILTER=MacSystemControlsTests.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RELAY_SYSTEM_TESTS"] == "1"))
func readsTheRealOutputVolume() throws {
    let volume = try CoreAudioVolume.volume()
    #expect((0...100).contains(volume))
}
