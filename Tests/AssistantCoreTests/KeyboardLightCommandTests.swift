import Foundation
import Testing
@testable import AssistantCore
@testable import Routing
@testable import SystemControls

@MainActor @Test func keyboardLightToAPercentage() async {
    let h = Harness(transcript: "keyboard backlight to 30 percent", outcome: .intent(.keyboardLight))
    await h.speak()
    #expect(await h.system.calls == ["keyboard(set(30))"])
    #expect(h.assistant.message == "Keyboard light 30%")
    #expect(h.assistant.resultLevel == 0.3)
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func keyboardLightOffAndOn() async {
    let off = Harness(transcript: "turn the keyboard light off", outcome: .intent(.keyboardLight))
    await off.speak()
    #expect(await off.system.calls == ["keyboard(set(0))"])
    #expect(off.assistant.message == "Keyboard light off")

    let on = Harness(transcript: "keyboard lights on", outcome: .intent(.keyboardLight))
    await on.speak()
    #expect(await on.system.calls == ["keyboard(set(50))"])
    #expect(on.assistant.message == "Keyboard light 50%")
}

@MainActor @Test func relativeKeyboardLight() async {
    let known = Harness(transcript: "keyboard brighter", outcome: .intent(.keyboardLight))
    await known.system.setKeyboardResult(56)
    await known.speak()
    #expect(await known.system.calls == ["keyboard(up(10))"])
    #expect(known.assistant.message == "Keyboard light 56%")

    let unknown = Harness(transcript: "dim the keyboard", outcome: .intent(.keyboardLight))
    await unknown.speak()
    #expect(await unknown.system.calls == ["keyboard(down(10))"])
    #expect(unknown.assistant.message == "Keyboard dimmer")
    #expect(unknown.assistant.resultLevel == nil)
}

@MainActor @Test func keyboardLightProblems() async {
    let unclear = Harness(transcript: "keyboard light banana", outcome: .intent(.keyboardLight))
    await unclear.speak()
    #expect(unclear.assistant.message == "What keyboard brightness? Try a percentage, like 50 percent.")

    let denied = Harness(transcript: "keyboard brighter", outcome: .intent(.keyboardLight))
    await denied.system.fail(with: .accessibilityDenied)
    await denied.speak()
    #expect(denied.assistant.message == "Relay needs Accessibility access to press keys for you.")
    #expect(denied.assistant.missingPermission == .accessibility)
}
