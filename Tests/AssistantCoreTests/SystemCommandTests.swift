import Foundation
import Testing
@testable import AssistantCore
@testable import Routing
@testable import SystemControls

@MainActor @Test func volumeSetToAPercentage() async {
    let h = Harness(transcript: "set volume to 40 percent", outcome: .intent(.volume))
    await h.speak()
    #expect(await h.system.calls == ["setVolume(40)", "setMuted(false)"])
    #expect(h.assistant.message == "Volume 40%")
    #expect(h.assistant.resultLevel == 0.4)
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func volumeUpStepsFromTheCurrentLevelAndUnmutes() async {
    let h = Harness(transcript: "turn the volume up", outcome: .intent(.volume))
    await h.speak()
    #expect(await h.system.calls == ["volume()", "setMuted(false)", "setVolume(60)"])
    #expect(h.assistant.message == "Volume 60%")
}

@MainActor @Test func volumeDownStopsAtZero() async {
    let h = Harness(transcript: "volume down", outcome: .intent(.volume))
    await h.system.setCurrentVolume(4)
    await h.speak()
    #expect(await h.system.calls == ["volume()", "setVolume(0)"])
    #expect(h.assistant.message == "Volume 0%")
    #expect(h.assistant.resultLevel == 0)
}

@MainActor @Test func muteAndUnmute() async {
    let h = Harness(transcript: "mute the sound", outcome: .intent(.volume))
    await h.speak()
    #expect(await h.system.calls == ["setMuted(true)"])
    #expect(h.assistant.message == "Muted")
    #expect(h.assistant.resultLevel == nil)

    let u = Harness(transcript: "unmute", outcome: .intent(.volume))
    await u.speak()
    #expect(await u.system.calls == ["setMuted(false)", "volume()"])
    #expect(u.assistant.message == "Unmuted")
    #expect(u.assistant.resultLevel == 0.5)
}

@MainActor @Test func unclearVolumeAsksForAPercentage() async {
    let h = Harness(transcript: "volume banana", outcome: .intent(.volume))
    await h.speak()
    #expect(await h.system.calls.isEmpty)
    #expect(h.assistant.message == "What volume? Try a percentage, like 40 percent.")
    #expect(h.assistant.resultKind == .info)
}

@MainActor @Test func brightnessSetAndStep() async {
    let h = Harness(transcript: "brightness to 70 percent", outcome: .intent(.brightness))
    await h.speak()
    #expect(await h.system.calls == ["setBrightness(70)"])
    #expect(h.assistant.message == "Brightness 70%")
    #expect(h.assistant.resultLevel == 0.7)

    let s = Harness(transcript: "a bit brighter", outcome: .intent(.brightness))
    await s.speak()
    #expect(await s.system.calls == ["stepBrightness(up: true, presses: 1)"])
    #expect(s.assistant.message == "Brighter")
    #expect(s.assistant.resultLevel == nil)

    let d = Harness(transcript: "dim the display", outcome: .intent(.brightness))
    await d.speak()
    #expect(await d.system.calls == ["stepBrightness(up: false, presses: 2)"])
    #expect(d.assistant.message == "Dimmer")
}

@MainActor @Test func unclearBrightnessAsksForAPercentage() async {
    let h = Harness(transcript: "brightness", outcome: .intent(.brightness))
    await h.speak()
    #expect(h.assistant.message == "What brightness? Try a percentage, like 70 percent.")
}

@MainActor @Test func darkModeFocusLockMediaAndScreenshot() async {
    let cases: [(String, RoutedIntent, String, String)] = [
        ("switch to light mode", .darkMode, "setDarkMode(off)", "Dark mode off"),
        ("switch to dark mode", .darkMode, "setDarkMode(on)", "Dark mode on"),
        ("dark mode", .darkMode, "setDarkMode(toggle)", "Switched appearance"),
        ("turn on do not disturb", .focus, "setFocus(true)", "Do Not Disturb on"),
        ("turn off do not disturb", .focus, "setFocus(false)", "Do Not Disturb off"),
        ("lock my mac", .lock, "lockScreen()", "Locking…"),
        ("pause", .mediaPlayPause, "pressMediaKey(playPause)", "Play/Pause"),
        ("next song", .mediaNext, "pressMediaKey(next)", "Next track"),
        ("previous track", .mediaPrevious, "pressMediaKey(previous)", "Previous track"),
        ("take a screenshot", .screenshot, "takeScreenshot()", "Screenshot saved to Desktop"),
    ]
    for (transcript, intent, call, message) in cases {
        let h = Harness(transcript: transcript, outcome: .intent(intent))
        await h.speak()
        #expect(await h.system.calls == [call], "\(transcript)")
        #expect(h.assistant.message == message, "\(transcript)")
        #expect(h.assistant.resultKind == .success, "\(transcript)")
    }
}

@MainActor @Test func missingShortcutAsksForSetup() async {
    let h = Harness(transcript: "brightness to 70 percent", outcome: .intent(.brightness))
    await h.system.fail(with: .shortcutMissing("Relay Brightness"))
    await h.speak()
    #expect(h.assistant.missingShortcut == "Relay Brightness")
    #expect(h.assistant.message == "Brightness needs a one-time setup.")
    #expect(h.assistant.resultKind == .info)

    let f = Harness(transcript: "turn on do not disturb", outcome: .intent(.focus))
    await f.system.fail(with: .shortcutMissing("Relay Focus On"))
    await f.speak()
    #expect(f.assistant.message == "Do Not Disturb needs a one-time setup.")
}

@MainActor @Test func permissionProblemsSayWhatToAllow() async {
    let cases: [(SystemControlError, RoutedIntent, String, PermissionKind)] = [
        (.accessibilityDenied, .lock, "Relay needs Accessibility access to press keys for you.", .accessibility),
        (.automationDenied, .darkMode, "Relay needs permission to control System Events for dark mode.", .automation),
        (.screenRecordingDenied, .screenshot, "Relay needs Screen Recording permission to take screenshots. Allow it, then quit and reopen Relay.", .screenRecording),
    ]
    for (error, intent, message, permission) in cases {
        let h = Harness(transcript: "do it", outcome: .intent(intent))
        await h.system.fail(with: error)
        await h.speak()
        #expect(h.assistant.message == message)
        #expect(h.assistant.missingPermission == permission)
        #expect(h.assistant.resultKind == .problem)
        #expect(h.assistant.phase == .idle)
    }
}

@MainActor @Test func deviceAndShortcutFailures() async {
    let v = Harness(transcript: "volume up", outcome: .intent(.volume))
    await v.system.fail(with: .noVolumeControl)
    await v.speak()
    #expect(v.assistant.message == "This audio device doesn't allow volume control.")

    let s = Harness(transcript: "brightness to 70 percent", outcome: .intent(.brightness))
    await s.system.fail(with: .shortcutFailed("Relay Brightness", reason: "exit 1"))
    await s.speak()
    #expect(s.assistant.message == "The Relay Brightness shortcut failed: exit 1")

    let x = Harness(transcript: "take a screenshot", outcome: .intent(.screenshot))
    await x.system.fail(with: .failed("disk full"))
    await x.speak()
    #expect(x.assistant.message == "Couldn't take a screenshot: disk full")
}

@MainActor @Test func grantedPermissionWorksNextTimeAndStalePromptsClear() async {
    let h = Harness(transcript: "lock my mac", outcome: .intent(.lock))
    await h.system.fail(with: .accessibilityDenied)
    await h.speak()
    #expect(h.assistant.missingPermission == .accessibility)

    await h.system.fail(with: nil)
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.missingPermission == nil)
    #expect(h.assistant.missingShortcut == nil)
    #expect(h.assistant.resultLevel == nil)
    await h.assistant.hotkeyPressed()
    #expect(h.assistant.message == "Locking…")
}

// MARK: Final-review findings

@MainActor @Test func volumeWorksOnDevicesWithoutAMuteControl() async {
    let h = Harness(transcript: "turn the volume up", outcome: .intent(.volume))
    await h.system.failMute(with: .noVolumeControl)
    await h.speak()
    #expect(await h.system.calls == ["volume()", "setMuted(false)", "setVolume(60)"])
    #expect(h.assistant.message == "Volume 60%")

    let s = Harness(transcript: "set volume to 40 percent", outcome: .intent(.volume))
    await s.system.failMute(with: .noVolumeControl)
    await s.speak()
    #expect(s.assistant.message == "Volume 40%")
}

@MainActor @Test func muteFallsBackToZeroVolumeWithoutAMuteControl() async {
    let h = Harness(transcript: "mute", outcome: .intent(.volume))
    await h.system.failMute(with: .noVolumeControl)
    await h.speak()
    #expect(await h.system.calls == ["setMuted(true)", "setVolume(0)"])
    #expect(h.assistant.message == "Volume 0%")
    #expect(h.assistant.resultLevel == 0)
}
