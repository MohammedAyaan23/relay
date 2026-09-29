# Relay distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Relay installable by end users: portable build (no KeyboardShortcuts), stable self-signed releases in a DMG, a daily GitHub update check, and a three-step welcome window.

**Architecture:** Pure logic (hotkey value and storage, version compare, update schedule and checker, welcome steps) goes in a new dependency-free `AppSupport` library with Swift Testing tests. RelayApp gets the Carbon `HotkeyCenter`, a `HotkeyRecorder` view, `UpdateController`, `WelcomeWindow`, and a `--self-check` launch mode that shell scripts use to prove the app runs without this checkout's `.build` folder.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, Carbon HIToolbox hot keys, URLSession, bash (`codesign`, `security`, `/usr/bin/openssl`, `hdiutil`, `plutil`).

**Spec:** `docs/superpowers/specs/2026-09-29-relay-distribution-design.md`

## Global Constraints

- Platform `.macOS("26.0")`, Apple Silicon (arm64) only; Command Line Tools only (no Xcode).
- No new third-party dependencies; KeyboardShortcuts is removed. No new models.
- Non-destructive: scripts never overwrite an existing DMG; `.build` is always restored after the portability check.
- Bundle ID `dev.relay.Relay`; signing identity name exactly `Relay Self-Signed`.
- UserDefaults keys: `hotkey`, legacy `KeyboardShortcuts_toggleListening`, `lastUpdateCheck`, `checkForUpdates` (default true), `welcomeSeen`.
- Default hotkey ⌥Space = keyCode 49, modifiers 2048. Carbon masks: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
- Update check: `GET https://api.github.com/repos/<owner/name>/releases/latest`, 10 s timeout, headers `Accept: application/vnd.github+json` and `User-Agent: Relay`, at most once per 24 h, silent on failure, no identifiers sent. Off while `ReleaseInfo.repository` is `""`.
- Exact user-facing strings: "That shortcut is taken, so try another"; "Add ⌘, ⌥, ⌃ or ⇧"; "Update available: v<version>…"; "You're up to date"; "Couldn't check. Try again later."; "Relay can't listen until this is allowed."; "Run scripts/make-signing-identity.sh first".
- Tests: `make test` (all), `make test FILTER=AppSupportTests`; `make test-routing` must stay 64/64.

## Review Focus

- A recorder abandoned mid-recording (Settings or welcome window closed while "Press keys…" shows) must restore the global hotkey — `onDisappear` calls `stop()`; covered by the manual checklist line in Task 10.
- An old KeyboardShortcuts value that isn't a JSON string (e.g. the boolean `false` it writes when a shortcut is cleared) must give ⌥Space, not a crash — test `legacyNonStringValueGivesDefault` in Task 1.
- A system clock set backwards (last check in the future) must not stop update checks forever — test `futureLastCheckIsDue` in Task 5.
- A malformed `ReleaseInfo.repository` (spaces, empty owner) must fail quietly instead of crashing on URL creation — test `malformedRepositoryFailsQuietly` in Task 5.
- An interrupted or failing portability check must still put `.build` back — Task 2 Step 6 verifies `.build` exists after a failing run.

---

### Task 1: AppSupport target with `Hotkey`, `HotkeyStore` and recording outcomes

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AppSupport/Hotkey.swift`
- Create: `Sources/AppSupport/HotkeyStore.swift`
- Test: `Tests/AppSupportTests/HotkeyTests.swift`

**Interfaces:**
- Produces:
  - `public struct Hotkey: Codable, Equatable, Sendable { keyCode: UInt32; modifiers: UInt32; init(keyCode:modifiers:); init(keyCode:command:option:control:shift:); static let default; var isValid: Bool; var displayText: String }`
  - `public enum RecordingOutcome: Equatable, Sendable { case cancel, needsModifier, accept(Hotkey) }` with `public static func recordingOutcome(keyCode: UInt32, command: Bool, option: Bool, control: Bool, shift: Bool) -> RecordingOutcome` on `Hotkey`
  - `public enum HotkeyStore { static let key = "hotkey"; static let legacyKey = "KeyboardShortcuts_toggleListening"; static func load(from: UserDefaults) -> Hotkey; static func save(_: Hotkey, to: UserDefaults) }`

- [ ] **Step 1: Add the targets to Package.swift**

Add after the HUDKit test target line:

```swift
        .target(name: "AppSupport"),
        .testTarget(name: "AppSupportTests", dependencies: ["AppSupport"]),
```

and add `"AppSupport",` to the start of RelayApp's dependency list (leave KeyboardShortcuts in place for now; Task 3 removes it).

- [ ] **Step 2: Write the failing tests**

`Tests/AppSupportTests/HotkeyTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSupport

private func freshDefaults() -> UserDefaults {
    let name = "relay-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func defaultIsOptionSpace() {
    #expect(Hotkey.default == Hotkey(keyCode: 49, modifiers: 2048))
    #expect(Hotkey.default.displayText == "⌥Space")
}

@Test func displayTextOrdersModifiersControlOptionShiftCommand() {
    #expect(Hotkey(keyCode: 15, command: true, option: false, control: true, shift: false).displayText == "⌃⌘R")
    #expect(Hotkey(keyCode: 96, command: false, option: false, control: false, shift: true).displayText == "⇧F5")
    #expect(Hotkey(keyCode: 0, command: true, option: true, control: true, shift: true).displayText == "⌃⌥⇧⌘A")
    #expect(Hotkey(keyCode: 126, command: false, option: true, control: false, shift: false).displayText == "⌥↑")
}

@Test func unknownKeyShowsItsNumber() {
    #expect(Hotkey(keyCode: 200, modifiers: 2048).displayText == "⌥Key 200")
}

@Test func validityNeedsAModifierAndANonModifierKey() {
    #expect(Hotkey.default.isValid)
    #expect(!Hotkey(keyCode: 49, modifiers: 0).isValid)
    #expect(!Hotkey(keyCode: 58, modifiers: 2048).isValid) // the Option key itself
}

@Test func recordingOutcomes() {
    #expect(Hotkey.recordingOutcome(keyCode: 53, command: false, option: false, control: false, shift: false) == .cancel)
    #expect(Hotkey.recordingOutcome(keyCode: 15, command: false, option: false, control: false, shift: false) == .needsModifier)
    #expect(Hotkey.recordingOutcome(keyCode: 15, command: true, option: false, control: true, shift: false)
        == .accept(Hotkey(keyCode: 15, modifiers: 256 | 4096)))
    // Esc with a modifier is an ordinary shortcut.
    #expect(Hotkey.recordingOutcome(keyCode: 53, command: true, option: false, control: false, shift: false)
        == .accept(Hotkey(keyCode: 53, modifiers: 256)))
}

@Test func storeRoundTrips() {
    let defaults = freshDefaults()
    let hotkey = Hotkey(keyCode: 15, modifiers: 256 | 4096)
    HotkeyStore.save(hotkey, to: defaults)
    #expect(HotkeyStore.load(from: defaults) == hotkey)
}

@Test func emptyStoreGivesDefault() {
    #expect(HotkeyStore.load(from: freshDefaults()) == .default)
}

@Test func migratesKeyboardShortcutsValue() {
    let defaults = freshDefaults()
    defaults.set(#"{"carbonKeyCode":15,"carbonModifiers":4352}"#, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: defaults) == Hotkey(keyCode: 15, modifiers: 4352))
    #expect(defaults.string(forKey: HotkeyStore.key) != nil) // written under the new key
}

@Test func newKeyWinsOverLegacy() {
    let defaults = freshDefaults()
    defaults.set(#"{"carbonKeyCode":15,"carbonModifiers":4352}"#, forKey: HotkeyStore.legacyKey)
    HotkeyStore.save(Hotkey(keyCode: 0, modifiers: 256), to: defaults)
    #expect(HotkeyStore.load(from: defaults) == Hotkey(keyCode: 0, modifiers: 256))
}

@Test func corruptOrInvalidValuesGiveDefault() {
    let corrupt = freshDefaults()
    corrupt.set("not json", forKey: HotkeyStore.key)
    #expect(HotkeyStore.load(from: corrupt) == .default)

    let noModifier = freshDefaults()
    noModifier.set(#"{"keyCode":15,"modifiers":0}"#, forKey: HotkeyStore.key)
    #expect(HotkeyStore.load(from: noModifier) == .default)

    let invalidLegacy = freshDefaults()
    invalidLegacy.set(#"{"carbonKeyCode":15,"carbonModifiers":0}"#, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: invalidLegacy) == .default)
}

@Test func legacyNonStringValueGivesDefault() {
    let defaults = freshDefaults()
    defaults.set(false, forKey: HotkeyStore.legacyKey)
    #expect(HotkeyStore.load(from: defaults) == .default)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test FILTER=AppSupportTests`
Expected: FAIL to compile with "cannot find 'Hotkey' in scope" (and `HotkeyStore`).

- [ ] **Step 4: Implement `Hotkey`**

`Sources/AppSupport/Hotkey.swift`:

```swift
/// A global shortcut as Carbon sees it: a virtual key code plus a Carbon modifier mask.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    private static let allModifiers = command | shift | option | control

    public static let `default` = Hotkey(keyCode: 49, modifiers: option) // ⌥Space

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, command: Bool, option: Bool, control: Bool, shift: Bool) {
        var mask: UInt32 = 0
        if command { mask |= Self.command }
        if option { mask |= Self.option }
        if control { mask |= Self.control }
        if shift { mask |= Self.shift }
        self.init(keyCode: keyCode, modifiers: mask)
    }

    /// At least one of ⌘⌥⌃⇧, on a key that isn't itself a modifier.
    public var isValid: Bool {
        modifiers & Self.allModifiers != 0 && !Self.modifierKeyCodes.contains(keyCode)
    }

    /// e.g. "⌥Space", "⌃⌘R".
    public var displayText: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// What the recorder does with a key press.
    public static func recordingOutcome(keyCode: UInt32, command: Bool, option: Bool, control: Bool, shift: Bool)
        -> RecordingOutcome {
        let hotkey = Hotkey(keyCode: keyCode, command: command, option: option, control: control, shift: shift)
        if hotkey.modifiers == 0 { return keyCode == 53 ? .cancel : .needsModifier }
        return hotkey.isValid ? .accept(hotkey) : .needsModifier
    }

    static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// ANSI-layout names for Carbon virtual key codes.
    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

public enum RecordingOutcome: Equatable, Sendable {
    case cancel
    case needsModifier
    case accept(Hotkey)
}
```

- [ ] **Step 5: Implement `HotkeyStore`**

`Sources/AppSupport/HotkeyStore.swift`:

```swift
import Foundation

/// Saves the hotkey as a JSON string, and migrates the value the KeyboardShortcuts package used to save.
public enum HotkeyStore {
    public static let key = "hotkey"
    public static let legacyKey = "KeyboardShortcuts_toggleListening"

    private struct Legacy: Decodable {
        let carbonKeyCode: UInt32
        let carbonModifiers: UInt32
    }

    public static func load(from defaults: UserDefaults) -> Hotkey {
        if defaults.object(forKey: key) != nil {
            return decode(Hotkey.self, from: defaults.object(forKey: key)).flatMap { $0.isValid ? $0 : nil } ?? .default
        }
        if let legacy = decode(Legacy.self, from: defaults.object(forKey: legacyKey)) {
            let hotkey = Hotkey(keyCode: legacy.carbonKeyCode, modifiers: legacy.carbonModifiers)
            if hotkey.isValid {
                save(hotkey, to: defaults)
                return hotkey
            }
        }
        return .default
    }

    public static func save(_ hotkey: Hotkey, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(hotkey), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        let data: Data? = switch value {
        case let text as String: text.data(using: .utf8)
        case let data as Data: data
        default: nil
        }
        return data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test FILTER=AppSupportTests`
Expected: PASS, 11 tests.

- [ ] **Step 7: Run the whole suite and commit**

Run: `make test > .superpowers/t1.log 2>&1; tail -5 .superpowers/t1.log`
Expected: all tests pass.

```bash
git add Package.swift Sources/AppSupport Tests/AppSupportTests
git commit -m "Add AppSupport with the Hotkey value, storage and migration"
```

---

### Task 2: `--self-check` and the portability check (proves the KeyboardShortcuts crash)

**Files:**
- Create: `Sources/RelayApp/SelfCheck.swift`
- Create: `Sources/RelayApp/AppInfo.swift`
- Modify: `Sources/RelayApp/RelayApp.swift` (AppDelegate)
- Create: `scripts/check-portable.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `HotkeyStore.load(from:)` (Task 1).
- Produces:
  - `@MainActor enum SelfCheck { static var isRequested: Bool; static func run(controller: AppController) -> Never }` with `static func check(_ name: String, _ view: some View)`
  - `enum AppInfo { static var version: String?; static var build: String?; static var displayText: String }`
  - `scripts/check-portable.sh [app path]` — exits 0 only if the app's self-check passes with `.build` hidden.

- [ ] **Step 1: Write `AppInfo`**

`Sources/RelayApp/AppInfo.swift`:

```swift
import Foundation

/// The version and build number from Relay.app's Info.plist (absent when run with `swift run`).
enum AppInfo {
    static var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    static var displayText: String {
        guard let version else { return "Relay (development build)" }
        return build.map { "Relay \(version) (build \($0))" } ?? "Relay \(version)"
    }
}
```

- [ ] **Step 2: Write `SelfCheck`**

`Sources/RelayApp/SelfCheck.swift`:

```swift
import AppKit
import AppSupport
import SwiftUI

/// `Relay --self-check`: draws every window Relay can show, then exits. `make release` runs it with this
/// checkout's `.build` folder hidden, so a view that needs a SwiftPM resource bundle crashes here, not on a
/// user's Mac.
@MainActor
enum SelfCheck {
    static var isRequested: Bool { CommandLine.arguments.contains("--self-check") }

    static func run(controller: AppController) -> Never {
        check("settings", SettingsView(controller: controller))
        check("panel", PanelView(assistant: controller.assistant, controller: controller))
        check("hud", HUDView(assistant: controller.assistant, model: HUDModel()))
        _ = HotkeyStore.load(from: UserDefaults(suiteName: "relay-self-check")!)
        print("self-check: version \(AppInfo.version ?? "none")")
        print("self-check ok")
        exit(0)
    }

    /// Puts the view in an off-screen window and draws it once, which runs its body and its AppKit views.
    static func check(_ name: String, _ view: some View) {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 480, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print("self-check: \(name) ok")
    }
}
```

- [ ] **Step 3: Hook it into launch**

In `Sources/RelayApp/RelayApp.swift`, change `applicationDidFinishLaunching` to:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfCheck.isRequested { SelfCheck.run(controller: controller) }
        controller.start()
    }
```

- [ ] **Step 4: Write the portability script and make target**

`scripts/check-portable.sh`:

```bash
#!/bin/bash
# Runs Relay.app's --self-check with this checkout's .build folder hidden, the way it runs on other Macs.
# SwiftPM's Bundle.module falls back to this checkout's absolute .build path, which hides a missing bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Relay.app}"

if [ -e .build-hidden ]; then
    echo ".build-hidden exists from an earlier run. Rename it back to .build first." >&2
    exit 1
fi
restore() {
    if [ -d .build-hidden ]; then mv .build-hidden .build; fi
}
trap restore EXIT
mv .build .build-hidden

if perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/Relay" --self-check; then
    echo "Portability check: ok"
else
    echo "Portability check failed: Relay crashed or hung without this checkout's .build folder." >&2
    exit 1
fi
```

Run `chmod +x scripts/check-portable.sh`. In `Makefile`, change the `.PHONY` line to
`.PHONY: build test test-routing test-speech app run check-portable` and add:

```make
check-portable: app
	scripts/check-portable.sh
```

- [ ] **Step 5: Run the check and watch it fail (KeyboardShortcuts still present)**

Run: `make check-portable 2>&1 | tail -8`
Expected: FAIL — output ends with "Portability check failed…", after a fatal error mentioning the KeyboardShortcuts resource bundle (`unable to find bundle named KeyboardShortcuts_KeyboardShortcuts`) while drawing `settings`. If "self-check: settings ok" prints instead, the self-check isn't exercising the recorder: use superpowers:systematic-debugging before continuing — this RED is what proves the check works.

- [ ] **Step 6: Confirm `.build` was restored after the failing run**

Run: `ls -d .build && ! ls -d .build-hidden 2>/dev/null && echo restored`
Expected: `.build` then `restored`.

- [ ] **Step 7: Commit**

```bash
git add Sources/RelayApp/SelfCheck.swift Sources/RelayApp/AppInfo.swift Sources/RelayApp/RelayApp.swift scripts/check-portable.sh Makefile
git commit -m "Add --self-check and a portability check that hides .build"
```

---

### Task 3: Carbon hotkey, recorder, and removing KeyboardShortcuts

**Files:**
- Create: `Sources/RelayApp/HotkeyCenter.swift`
- Create: `Sources/RelayApp/HotkeyRecorder.swift`
- Modify: `Sources/RelayApp/AppController.swift`
- Modify: `Sources/RelayApp/Preferences.swift`
- Modify: `Sources/RelayApp/SettingsView.swift`
- Modify: `Package.swift`, `Package.resolved`
- Modify: `scripts/make-app.sh` (comment only)

**Interfaces:**
- Consumes: `Hotkey`, `HotkeyStore`, `Hotkey.recordingOutcome` (Task 1); `scripts/check-portable.sh` (Task 2).
- Produces:
  - `@MainActor final class HotkeyCenter { static let shared; var onPress: () -> Void; private(set) var current: Hotkey?; func register(_: Hotkey) -> Bool; func suspend(); func resume() }`
  - `struct HotkeyRecorder: View` (no parameters; reads and writes `HotkeyStore` with `.standard`)

- [ ] **Step 1: Write `HotkeyCenter`**

`Sources/RelayApp/HotkeyCenter.swift`:

```swift
import AppSupport
import Carbon.HIToolbox

/// The global hotkey, through Carbon's RegisterEventHotKey (no permission needed).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onPress: () -> Void = {}
    /// The hotkey Relay wants, kept while suspended for recording.
    private(set) var current: Hotkey?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Replaces the hotkey. If the new one can't be registered, the previous one is put back and this returns false.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        installHandler()
        let previous = current
        unregisterRef()
        if registerRef(hotkey) {
            current = hotkey
            return true
        }
        if let previous, registerRef(previous) { current = previous }
        return false
    }

    /// Stops listening for the hotkey (while the recorder takes a key press).
    func suspend() {
        unregisterRef()
    }

    /// Listens for the current hotkey again after `suspend()`.
    func resume() {
        if ref == nil, let current { _ = registerRef(current) }
    }

    private func registerRef(_ hotkey: Hotkey) -> Bool {
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x524C_4159), id: 1) // "RLAY"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        ref = newRef
        return true
    }

    private func unregisterRef() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotkeyCenter.shared.onPress() }
            return noErr
        }, 1, &type, nil, &handler)
    }
}
```

- [ ] **Step 2: Write `HotkeyRecorder`**

`Sources/RelayApp/HotkeyRecorder.swift`:

```swift
import AppKit
import AppSupport
import SwiftUI

/// Shows the hotkey and records a new one: press a combination with ⌘, ⌥, ⌃ or ⇧; Esc cancels.
struct HotkeyRecorder: View {
    @State private var hotkey = HotkeyStore.load(from: .standard)
    @State private var recording = false
    @State private var note: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Start/stop listening:")
                Button(recording ? "Press keys…" : hotkey.displayText) {
                    recording ? stop() : start()
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        note = "Press a shortcut, or Esc to cancel."
        recording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags
        let outcome = Hotkey.recordingOutcome(
            keyCode: UInt32(event.keyCode), command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift))
        switch outcome {
        case .cancel:
            note = nil
            stop()
        case .needsModifier:
            note = "Add ⌘, ⌥, ⌃ or ⇧"
        case .accept(let newHotkey):
            if HotkeyCenter.shared.register(newHotkey) {
                HotkeyStore.save(newHotkey, to: .standard)
                hotkey = newHotkey
                note = nil
            } else {
                note = "That shortcut is taken, so try another"
            }
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotkeyCenter.shared.resume()
    }
}
```

- [ ] **Step 3: Switch AppController to `HotkeyCenter`**

In `Sources/RelayApp/AppController.swift`: replace `@preconcurrency import KeyboardShortcuts` with `import AppSupport`, and replace the whole `KeyboardShortcuts.onKeyUp(for: .toggleListening) { … }` block in `start()` with:

```swift
        HotkeyCenter.shared.onPress = { [weak self] in self?.hotkeyFired() }
        let hotkey = HotkeyStore.load(from: .standard)
        if !HotkeyCenter.shared.register(hotkey) {
            Notifier.post(title: "Relay's shortcut is taken",
                          body: "\(hotkey.displayText) is taken by another app. Choose a different shortcut in Relay's Settings.")
        }
```

and add this method below `start()`:

```swift
    private func hotkeyFired() {
        // A light tap on the trackpad (if a finger is on it) confirms start/stop.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        hud.present()
        Task {
            await assistant.hotkeyPressed()
            // Still listening: keep the pill. Otherwise show the result briefly, then fade.
            if assistant.phase != .listening { hud.scheduleHide() }
        }
    }
```

- [ ] **Step 4: Remove KeyboardShortcuts from Preferences and Settings**

In `Sources/RelayApp/Preferences.swift`, delete the `@preconcurrency import KeyboardShortcuts` line and the whole `extension KeyboardShortcuts.Name { … }` block.

In `Sources/RelayApp/SettingsView.swift`, replace `@preconcurrency import KeyboardShortcuts` with nothing (keep `import SwiftUI`) and replace the line
`KeyboardShortcuts.Recorder("Start/stop listening:", name: .toggleListening)` with `HotkeyRecorder()`.

- [ ] **Step 5: Remove the package**

In `Package.swift`, delete the line `.package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.10.0"),` and the line `.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),` from RelayApp's dependencies. Then run:

Run: `swift package resolve && grep -c KeyboardShortcuts Package.resolved Package.swift; grep -rn KeyboardShortcuts Sources | grep -v HotkeyStore`
Expected: `Package.resolved:0`, `Package.swift:0`, and no Sources lines (only `HotkeyStore.swift` mentions the legacy key).

In `scripts/make-app.sh`, change the header comment's second paragraph to:

```bash
# SwiftPM resource bundles are looked up at the .app root, which codesign rejects, and then in this
# checkout's .build folder. Relay must not call Bundle.module; `make check-portable` proves it doesn't.
```

- [ ] **Step 6: Run the portability check and watch it pass**

Run: `make check-portable 2>&1 | tail -6`
Expected: PASS — "self-check: settings ok", "self-check: panel ok", "self-check: hud ok", "self-check ok", "Portability check: ok".

- [ ] **Step 7: Run the whole suite, then commit**

Run: `make test > .superpowers/t3.log 2>&1; tail -5 .superpowers/t3.log`
Expected: all tests pass, with no warnings mentioning KeyboardShortcuts.

```bash
git add -A Sources/RelayApp Package.swift Package.resolved scripts/make-app.sh
git commit -m "Replace KeyboardShortcuts with a built-in Carbon hotkey and recorder"
```

---

### Task 4: Version file, versioned and signable app bundle, `AppVersion`

**Files:**
- Create: `VERSION`
- Modify: `scripts/make-app.sh`
- Create: `Sources/AppSupport/AppVersion.swift`
- Test: `Tests/AppSupportTests/AppVersionTests.swift`
- Modify: `Sources/RelayApp/SettingsView.swift`

**Interfaces:**
- Consumes: `AppInfo.displayText` (Task 2).
- Produces:
  - `public struct AppVersion: Comparable, Sendable, CustomStringConvertible { let parts: [Int]; init?(_ text: String) }`
  - `make-app.sh` honours `RELAY_VERSION` (default: `VERSION` file) and `RELAY_SIGN_IDENTITY` (default `-`).

- [ ] **Step 1: Write the failing tests**

`Tests/AppSupportTests/AppVersionTests.swift`:

```swift
import Testing
@testable import AppSupport

@Test func parsesWithAndWithoutV() {
    #expect(AppVersion("0.2.0")?.parts == [0, 2, 0])
    #expect(AppVersion("v1.10.3")?.parts == [1, 10, 3])
    #expect(AppVersion("V2")?.parts == [2])
}

@Test func junkIsNil() {
    for junk in ["", "latest", "1.x", "v", "1..2", "-1.0", "+1.0", "1.0-beta", "1.2.3.4.5"] {
        #expect(AppVersion(junk) == nil, "\(junk)")
    }
}

@Test func comparesNumericallyPartByPart() {
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.2")!)
    #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
    #expect(AppVersion("1.0.1")! > AppVersion("1.0")!)
    #expect(AppVersion("v0.2.0")! > AppVersion("0.1.9")!)
    #expect(!(AppVersion("0.2.0")! > AppVersion("0.2.0")!))
}

@Test func descriptionJoinsParts() {
    #expect(AppVersion("v0.2.0")?.description == "0.2.0")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=AppVersionTests`
Expected: FAIL to compile with "cannot find 'AppVersion' in scope".

- [ ] **Step 3: Implement `AppVersion`**

`Sources/AppSupport/AppVersion.swift`:

```swift
/// A dotted version such as "0.10.2" or "v0.10.2". Missing trailing parts count as 0.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = Substring(text)
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        return lhs.padded(to: count) == rhs.padded(to: count)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        return lhs.padded(to: count).lexicographicallyPrecedes(rhs.padded(to: count))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=AppVersionTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Add `VERSION` and version/sign support in make-app.sh**

Create `VERSION` containing the single line `0.1.0`.

In `scripts/make-app.sh`, after `cd "$(dirname "$0")/.."` add:

```bash
VERSION="${RELAY_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${RELAY_SIGN_IDENTITY:--}" # "-" = local ad-hoc signature (development)
```

Replace the two build lines with:

```bash
swift build -c release --arch arm64 --product Relay
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
```

After `cp Resources/Info.plist "$APP/Contents/Info.plist"` add:

```bash
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
```

Replace `codesign --force --sign - "$APP"` with `codesign --force --sign "$IDENTITY" "$APP"`, and replace the final echo with `echo "Built $APP ($VERSION, build $BUILD_NUMBER)"`.

- [ ] **Step 6: Show the version in Settings**

In `Sources/RelayApp/SettingsView.swift`, add as the last item inside the `Form`:

```swift
            Text(AppInfo.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
```

- [ ] **Step 7: Verify the bundle**

Run: `make app && plutil -extract CFBundleShortVersionString raw build/Relay.app/Contents/Info.plist && plutil -extract CFBundleVersion raw build/Relay.app/Contents/Info.plist && lipo -archs build/Relay.app/Contents/MacOS/Relay`
Expected: "Built build/Relay.app (0.1.0, build N)", then `0.1.0`, the commit count, and `arm64`.

- [ ] **Step 8: Run the whole suite and commit**

Run: `make test > .superpowers/t4.log 2>&1; tail -5 .superpowers/t4.log`
Expected: all tests pass.

```bash
git add VERSION scripts/make-app.sh Sources/AppSupport/AppVersion.swift Tests/AppSupportTests/AppVersionTests.swift Sources/RelayApp/SettingsView.swift
git commit -m "Version Relay from a VERSION file and allow signing with a chosen identity"
```

---

### Task 5: Update schedule, release feed and checker (AppSupport)

**Files:**
- Create: `Sources/AppSupport/UpdateCheck.swift`
- Test: `Tests/AppSupportTests/UpdateCheckTests.swift`

**Interfaces:**
- Consumes: `AppVersion` (Task 4).
- Produces:
  - `public enum UpdateSchedule { static let interval: TimeInterval; static func isDue(lastCheck: Date?, now: Date) -> Bool }`
  - `public struct ReleaseSummary: Equatable, Sendable { tag: String; url: URL; draft: Bool; prerelease: Bool }`
  - `public protocol ReleaseFeed: Sendable { func latest() async throws -> ReleaseSummary }`
  - `public struct GitHubReleaseFeed: ReleaseFeed { init(repository: String); static func decode(_: Data) throws -> ReleaseSummary }`
  - `public enum UpdateResult: Equatable, Sendable { case upToDate, available(version: String, url: URL), failed }`
  - `public enum UpdateChecker { static func check(current: String, feed: some ReleaseFeed) async -> UpdateResult }`

- [ ] **Step 1: Write the failing tests**

`Tests/AppSupportTests/UpdateCheckTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSupport

private struct FakeFeed: ReleaseFeed {
    var result: Result<ReleaseSummary, URLError>
    func latest() async throws -> ReleaseSummary { try result.get() }
}

private let page = URL(string: "https://github.com/me/relay/releases/tag/v0.2.0")!

private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> FakeFeed {
    FakeFeed(result: .success(ReleaseSummary(tag: tag, url: page, draft: draft, prerelease: prerelease)))
}

@Test func scheduleIsDueWithoutALastCheck() {
    #expect(UpdateSchedule.isDue(lastCheck: nil, now: .now))
}

@Test func scheduleWaits24Hours() {
    let now = Date()
    #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
    #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
}

@Test func futureLastCheckIsDue() {
    let now = Date()
    #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
}

@Test func newerReleaseIsAvailable() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0")) == .available(version: "0.2.0", url: page))
}

@Test func sameOrOlderIsUpToDate() async {
    #expect(await UpdateChecker.check(current: "0.2.0", feed: release("v0.2.0")) == .upToDate)
    #expect(await UpdateChecker.check(current: "0.10.0", feed: release("v0.9.9")) == .upToDate)
}

@Test func draftsAndPrereleasesAreIgnored() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0", draft: true)) == .upToDate)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("v0.2.0", prerelease: true)) == .upToDate)
}

@Test func junkTagOrErrorFails() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: release("nightly")) == .failed)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: FakeFeed(result: .failure(URLError(.notConnectedToInternet)))) == .failed)
    #expect(await UpdateChecker.check(current: "dev", feed: release("v0.2.0")) == .failed)
}

@Test func decodesGitHubReleaseJSON() throws {
    let json = """
    {"url":"https://api.github.com/repos/me/relay/releases/1","html_url":"https://github.com/me/relay/releases/tag/v0.2.0",
     "id":1,"tag_name":"v0.2.0","name":"Relay 0.2.0","draft":false,"prerelease":false,
     "assets":[{"name":"Relay-0.2.0.dmg","size":123}],"body":"Notes"}
    """
    let summary = try GitHubReleaseFeed.decode(Data(json.utf8))
    #expect(summary == ReleaseSummary(tag: "v0.2.0", url: page, draft: false, prerelease: false))
}

@Test func badJSONThrows() {
    #expect(throws: (any Error).self) { try GitHubReleaseFeed.decode(Data("{\"message\":\"Not Found\"}".utf8)) }
}

@Test func malformedRepositoryFailsQuietly() async {
    #expect(await UpdateChecker.check(current: "0.1.0", feed: GitHubReleaseFeed(repository: "not a repo")) == .failed)
    #expect(await UpdateChecker.check(current: "0.1.0", feed: GitHubReleaseFeed(repository: "/relay")) == .failed)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=UpdateCheckTests`
Expected: FAIL to compile with "cannot find type 'ReleaseFeed' in scope".

- [ ] **Step 3: Implement**

`Sources/AppSupport/UpdateCheck.swift`:

```swift
import Foundation

/// Checks run at most once a day. A last check in the future (clock set back) counts as due.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}

public struct ReleaseSummary: Equatable, Sendable {
    public let tag: String
    public let url: URL
    public let draft: Bool
    public let prerelease: Bool

    public init(tag: String, url: URL, draft: Bool, prerelease: Bool) {
        self.tag = tag
        self.url = url
        self.draft = draft
        self.prerelease = prerelease
    }
}

public protocol ReleaseFeed: Sendable {
    func latest() async throws -> ReleaseSummary
}

/// GitHub's "latest release" endpoint, without authentication. Sends nothing about the user.
public struct GitHubReleaseFeed: ReleaseFeed {
    public let repository: String

    public init(repository: String) {
        self.repository = repository
    }

    public func latest() async throws -> ReleaseSummary {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Relay", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data)
    }

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }

    public static func decode(_ data: Data) throws -> ReleaseSummary {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseSummary(tag: payload.tag_name, url: payload.html_url, draft: payload.draft, prerelease: payload.prerelease)
    }
}

public enum UpdateResult: Equatable, Sendable {
    case upToDate
    case available(version: String, url: URL)
    case failed
}

public enum UpdateChecker {
    /// Never throws or alerts: any problem is `.failed`, and the next scheduled check tries again.
    public static func check(current: String, feed: some ReleaseFeed) async -> UpdateResult {
        guard let mine = AppVersion(current), let latest = try? await feed.latest() else { return .failed }
        if latest.draft || latest.prerelease { return .upToDate }
        guard let theirs = AppVersion(latest.tag) else { return .failed }
        return theirs > mine ? .available(version: theirs.description, url: latest.url) : .upToDate
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=UpdateCheckTests`
Expected: PASS, 10 tests (the malformed-repository test never touches the network).

- [ ] **Step 5: Run the whole suite and commit**

Run: `make test > .superpowers/t5.log 2>&1; tail -5 .superpowers/t5.log`
Expected: all tests pass.

```bash
git add Sources/AppSupport/UpdateCheck.swift Tests/AppSupportTests/UpdateCheckTests.swift
git commit -m "Add the daily update schedule, GitHub release feed and update checker"
```

---

### Task 6: Update check in the app (menu item, Settings)

**Files:**
- Create: `Sources/RelayApp/ReleaseInfo.swift`
- Create: `Sources/RelayApp/UpdateController.swift`
- Modify: `Sources/RelayApp/Preferences.swift`
- Modify: `Sources/RelayApp/AppController.swift`
- Modify: `Sources/RelayApp/MenuContent.swift`
- Modify: `Sources/RelayApp/SettingsView.swift`

**Interfaces:**
- Consumes: `UpdateSchedule`, `UpdateChecker`, `GitHubReleaseFeed`, `UpdateResult` (Task 5); `AppInfo.version` (Task 2).
- Produces:
  - `enum ReleaseInfo { static let repository: String }`
  - `@MainActor @Observable final class UpdateController { struct Available { version: String; url: URL }; private(set) var available: Available?; private(set) var manualStatus: String?; var isConfigured: Bool; func start(); func checkNow() async }`
  - `AppController.updates: UpdateController`
  - `Preferences.checkForUpdates = "checkForUpdates"`, `Preferences.lastUpdateCheck = "lastUpdateCheck"`

- [ ] **Step 1: Add the release location and preference keys**

`Sources/RelayApp/ReleaseInfo.swift`:

```swift
/// Where Relay's releases are published, as "owner/name" on GitHub. Empty turns the update check off.
enum ReleaseInfo {
    static let repository = ""
}
```

In `Sources/RelayApp/Preferences.swift`, add below `choiceThreshold`:

```swift
    static let checkForUpdates = "checkForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
```

and change `registerDefaults` to register `checkForUpdates: true` as well:

```swift
        UserDefaults.standard.register(defaults: [gateThreshold: 0.5, choiceThreshold: 0.35, checkForUpdates: true])
```

- [ ] **Step 2: Write `UpdateController`**

`Sources/RelayApp/UpdateController.swift`:

```swift
import AppSupport
import Foundation
import Observation

/// Asks GitHub for a newer Relay at most once a day, and on "Check now". Never downloads or installs.
@MainActor @Observable
final class UpdateController {
    struct Available: Equatable {
        let version: String
        let url: URL
    }

    private(set) var available: Available?
    private(set) var manualStatus: String?

    var isConfigured: Bool { !ReleaseInfo.repository.isEmpty }

    func start() {
        guard isConfigured else { return }
        Task {
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func checkNow() async {
        manualStatus = "Checking…"
        let result = await check()
        UserDefaults.standard.set(Date.now, forKey: Preferences.lastUpdateCheck)
        apply(result)
        manualStatus = switch result {
        case .upToDate: "You're up to date"
        case .available(let version, _): "Update available: v\(version)"
        case .failed: "Couldn't check. Try again later."
        }
    }

    private func checkIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Preferences.checkForUpdates),
              UpdateSchedule.isDue(lastCheck: defaults.object(forKey: Preferences.lastUpdateCheck) as? Date, now: .now)
        else { return }
        defaults.set(Date.now, forKey: Preferences.lastUpdateCheck)
        apply(await check())
    }

    private func check() async -> UpdateResult {
        await UpdateChecker.check(current: AppInfo.version ?? "0.0.0",
                                  feed: GitHubReleaseFeed(repository: ReleaseInfo.repository))
    }

    /// A failed check keeps whatever was known before.
    private func apply(_ result: UpdateResult) {
        switch result {
        case .available(let version, let url): available = Available(version: version, url: url)
        case .upToDate: available = nil
        case .failed: break
        }
    }
}
```

- [ ] **Step 3: Wire it into AppController**

In `Sources/RelayApp/AppController.swift`, add the property below `let assistant: Assistant`:

```swift
    let updates = UpdateController()
```

and add `updates.start()` in `start()` directly after `watchForPanelWorthyChanges()`.

- [ ] **Step 4: Menu item**

In `Sources/RelayApp/MenuContent.swift`, add at the top of `body` (before the project `Text`):

```swift
        if let update = controller.updates.available {
            Button("Update available: v\(update.version)…") { NSWorkspace.shared.open(update.url) }
            Divider()
        }
```

- [ ] **Step 5: Settings controls**

In `Sources/RelayApp/SettingsView.swift`, add the property:

```swift
    @AppStorage(Preferences.checkForUpdates) private var checkForUpdates = true
```

and, just above the `Text(AppInfo.displayText)` added in Task 4, insert:

```swift
            if controller.updates.isConfigured {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Button("Check now") { Task { await controller.updates.checkNow() } }
                    if let update = controller.updates.available, controller.updates.manualStatus?.hasPrefix("Update") == true {
                        Link("Update available: v\(update.version)", destination: update.url)
                    } else if let status = controller.updates.manualStatus {
                        Text(status).foregroundStyle(.secondary)
                    }
                }
            }
```

- [ ] **Step 6: Build, run the self-check, run the suite**

Run: `make check-portable 2>&1 | tail -3 && make test > .superpowers/t6.log 2>&1; tail -5 .superpowers/t6.log`
Expected: "Portability check: ok", then all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/RelayApp
git commit -m "Show available updates in the menu and add update settings"
```

---

### Task 7: `WelcomeFlow` logic (AppSupport)

**Files:**
- Create: `Sources/AppSupport/WelcomeFlow.swift`
- Test: `Tests/AppSupportTests/WelcomeFlowTests.swift`

**Interfaces:**
- Produces:
  - `public enum WelcomeStep: Int, CaseIterable, Sendable { case meet, setup, tryIt }`
  - `public struct WelcomeFlow: Equatable, Sendable { init(step: WelcomeStep = .meet); private(set) var step; var isFirst: Bool; var isLast: Bool; mutating func next(); mutating func back(); static let seenKey = "welcomeSeen"; static func shouldShowOnLaunch(_: UserDefaults) -> Bool; static func markSeen(_: UserDefaults) }`
  - `public enum PermissionRow { public enum State: Equatable, Sendable { case granted, notAsked, denied; var buttonTitle: String? } }`

- [ ] **Step 1: Write the failing tests**

`Tests/AppSupportTests/WelcomeFlowTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSupport

@Test func stepsAdvanceAndClamp() {
    var flow = WelcomeFlow()
    #expect(flow.step == .meet && flow.isFirst)
    flow.back()
    #expect(flow.step == .meet)
    flow.next()
    #expect(flow.step == .setup)
    flow.next()
    #expect(flow.step == .tryIt && flow.isLast)
    flow.next()
    #expect(flow.step == .tryIt)
    flow.back()
    #expect(flow.step == .setup)
}

@Test func showsUntilMarkedSeen() {
    let name = "relay-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(WelcomeFlow.shouldShowOnLaunch(defaults))
    WelcomeFlow.markSeen(defaults)
    #expect(!WelcomeFlow.shouldShowOnLaunch(defaults))
}

@Test func permissionButtonTitles() {
    #expect(PermissionRow.State.granted.buttonTitle == nil)
    #expect(PermissionRow.State.notAsked.buttonTitle == "Allow")
    #expect(PermissionRow.State.denied.buttonTitle == "Open Settings")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=WelcomeFlowTests`
Expected: FAIL to compile with "cannot find 'WelcomeFlow' in scope".

- [ ] **Step 3: Implement**

`Sources/AppSupport/WelcomeFlow.swift`:

```swift
import Foundation

public enum WelcomeStep: Int, CaseIterable, Sendable {
    case meet, setup, tryIt
}

/// Which welcome step is showing, and whether the welcome has been seen.
public struct WelcomeFlow: Equatable, Sendable {
    public static let seenKey = "welcomeSeen"

    public private(set) var step: WelcomeStep

    public init(step: WelcomeStep = .meet) {
        self.step = step
    }

    public var isFirst: Bool { step == WelcomeStep.allCases.first }
    public var isLast: Bool { step == WelcomeStep.allCases.last }

    public mutating func next() {
        step = WelcomeStep(rawValue: step.rawValue + 1) ?? step
    }

    public mutating func back() {
        step = WelcomeStep(rawValue: step.rawValue - 1) ?? step
    }

    public static func shouldShowOnLaunch(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: seenKey)
    }

    public static func markSeen(_ defaults: UserDefaults) {
        defaults.set(true, forKey: seenKey)
    }
}

public enum PermissionRow {
    public enum State: Equatable, Sendable {
        case granted, notAsked, denied

        public var buttonTitle: String? {
            switch self {
            case .granted: nil
            case .notAsked: "Allow"
            case .denied: "Open Settings"
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=WelcomeFlowTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run the whole suite and commit**

Run: `make test > .superpowers/t7.log 2>&1; tail -5 .superpowers/t7.log`
Expected: all tests pass.

```bash
git add Sources/AppSupport/WelcomeFlow.swift Tests/AppSupportTests/WelcomeFlowTests.swift
git commit -m "Add welcome step logic"
```

---

### Task 8: Welcome window

**Files:**
- Create: `Sources/RelayApp/WelcomeView.swift`
- Create: `Sources/RelayApp/WelcomeWindow.swift`
- Modify: `Sources/RelayApp/AppController.swift`
- Modify: `Sources/RelayApp/MenuContent.swift`
- Modify: `Sources/RelayApp/SelfCheck.swift`

**Interfaces:**
- Consumes: `WelcomeFlow`, `WelcomeStep`, `PermissionRow.State` (Task 7); `HotkeyRecorder`, `HotkeyStore` (Tasks 1, 3); `ReleaseInfo` (Task 6); `AppController.retryPrepare()`, `openPrivacySettings(for:)`, `assistant.phase/message/prepareFailed`; `ClaudeLocator.locate(override:)` (Actions); `Preferences.claudePathOverride`.
- Produces:
  - `struct WelcomeView: View { init(controller: AppController, startAt: WelcomeStep = .meet, onDone: @escaping () -> Void = {}) }`
  - `@MainActor final class WelcomeWindow { init(controller: AppController); func show() }`
  - `AppController.showWelcome()`

- [ ] **Step 1: Write `WelcomeView`**

`Sources/RelayApp/WelcomeView.swift`:

```swift
import Actions
import AppSupport
import AVFoundation
import Speech
import SwiftUI

/// The three-step first-launch welcome: meet Relay, set up permissions and the model, try a command.
struct WelcomeView: View {
    let controller: AppController
    var onDone: () -> Void
    @State private var flow: WelcomeFlow
    @State private var microphone = PermissionRow.State.notAsked
    @State private var speech = PermissionRow.State.notAsked
    @State private var claudeFound: Bool?

    init(controller: AppController, startAt: WelcomeStep = .meet, onDone: @escaping () -> Void = {}) {
        self.controller = controller
        self.onDone = onDone
        _flow = State(initialValue: WelcomeFlow(step: startAt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch flow.step {
            case .meet: meet
            case .setup: setup
            case .tryIt: tryIt
            }
            Spacer(minLength: 0)
            HStack {
                if !flow.isFirst { Button("Back") { flow.back() } }
                Spacer()
                if flow.isLast {
                    Button("Done", action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { flow.next() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .task {
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var meet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Relay").font(.title2.bold())
            Text("Relay does things on your Mac when you ask out loud.")
            HotkeyRecorder()
            Text("Relay lives in the menu bar, look for its icon at the top right.")
                .foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up").font(.title2.bold())
            permissionRow("Microphone", state: microphone, kind: .microphone) {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    retryIfWaiting()
                }
            }
            permissionRow("Speech Recognition", state: speech, kind: .speechRecognition) {
                SFSpeechRecognizer.requestAuthorization { _ in
                    Task { @MainActor in retryIfWaiting() }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Laya model").frame(width: 150, alignment: .leading)
                if controller.assistant.prepareFailed {
                    Text(controller.assistant.message ?? "Couldn't load the model.").foregroundStyle(.secondary)
                    Button("Try again") { controller.retryPrepare() }
                } else if controller.assistant.phase == .preparing {
                    Text(controller.assistant.message ?? "Getting ready…").foregroundStyle(.secondary)
                } else {
                    Text("Ready ✓")
                }
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it").font(.title2.bold())
            Text("Press \(HotkeyStore.load(from: .standard).displayText), say \"open Safari\", then press it again.")
            Text("Also try: \"search the web for pasta recipes\", \"set volume to 30\", \"remind me to call mum at 5pm\".")
                .foregroundStyle(.secondary)
            Text("Optional").font(.headline).padding(.top, 6)
            HStack {
                Text("Claude Code:")
                switch claudeFound {
                case .some(true): Text("found ✓")
                case .some(false):
                    Text("not found")
                    Link("Install", destination: URL(string: "https://claude.com/product/claude-code")!)
                case .none: Text("checking…").foregroundStyle(.secondary)
                }
            }
            Text("Accessibility: asked the first time you use typing or window commands.")
            if ReleaseInfo.repository.isEmpty {
                Text("Brightness and Focus: Relay shows the setup steps the first time you ask.")
            } else {
                Link("Brightness and Focus: how to set them up",
                     destination: URL(string: "https://github.com/\(ReleaseInfo.repository)#brightness-and-focus")!)
            }
        }
        .task {
            let override = UserDefaults.standard.string(forKey: Preferences.claudePathOverride)
            claudeFound = await Task.detached { ClaudeLocator.locate(override: override) != nil }.value
        }
    }

    private func permissionRow(_ title: String, state: PermissionRow.State, kind: PermissionKind,
                               allow: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).frame(width: 150, alignment: .leading)
                if state == .granted { Text("✓") }
                if let button = state.buttonTitle {
                    Button(button) {
                        if state == .denied { controller.openPrivacySettings(for: kind) } else { allow() }
                    }
                }
            }
            if state != .granted {
                Text("Relay can't listen until this is allowed.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshPermissions() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        speech = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Once a permission is granted, finish the setup that stopped waiting for it.
    private func retryIfWaiting() {
        refreshPermissions()
        if controller.assistant.missingPermission != nil { controller.retryPrepare() }
    }
}
```

- [ ] **Step 2: Write `WelcomeWindow`**

`Sources/RelayApp/WelcomeWindow.swift`:

```swift
import AppKit
import AppSupport
import SwiftUI

/// A normal window for the welcome steps. Closing it at any step counts as seen.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private let controller: AppController
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.title = "Welcome to Relay"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WelcomeView(controller: controller) { [weak window] in
                window?.close()
            })
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        WelcomeFlow.markSeen(.standard)
        // A fresh window (starting at step 1) next time "Welcome…" is chosen.
        window = nil
    }
}
```

- [ ] **Step 3: Show it on first launch and from the menu**

In `Sources/RelayApp/AppController.swift`, add below the `hud` property:

```swift
    private lazy var welcome = WelcomeWindow(controller: self)
```

in `start()`, directly after `updates.start()`, add:

```swift
        if WelcomeFlow.shouldShowOnLaunch(.standard) { welcome.show() }
```

and add the method (next to `showPanel()`):

```swift
    func showWelcome() {
        welcome.show()
    }
```

In `Sources/RelayApp/MenuContent.swift`, add below `Button("Show Panel") { controller.showPanel() }`:

```swift
        Button("Welcome…") { controller.showWelcome() }
```

- [ ] **Step 4: Add the welcome steps to the self-check**

In `Sources/RelayApp/SelfCheck.swift`, add after the `hud` check line:

```swift
        for step in WelcomeStep.allCases {
            check("welcome-\(step)", WelcomeView(controller: controller, startAt: step))
        }
```

- [ ] **Step 5: Run the portability check**

Run: `make check-portable 2>&1 | tail -8`
Expected: "self-check: welcome-meet ok", "self-check: welcome-setup ok", "self-check: welcome-tryIt ok", "self-check ok", "Portability check: ok".

- [ ] **Step 6: Run the whole suite and commit**

Run: `make test > .superpowers/t8.log 2>&1; tail -5 .superpowers/t8.log`
Expected: all tests pass.

```bash
git add Sources/RelayApp
git commit -m "Add the three-step welcome window"
```

---

### Task 9: Signing identity script, `make release` and the DMG

**Files:**
- Create: `scripts/make-signing-identity.sh`
- Create: `scripts/make-release.sh`
- Create: `Resources/First launch.txt`
- Modify: `Makefile`, `.gitignore`

**Interfaces:**
- Consumes: `make-app.sh` env vars `RELAY_VERSION`, `RELAY_SIGN_IDENTITY` (Task 4); `scripts/check-portable.sh` (Task 2); `VERSION`.
- Produces: `make release` → `dist/Relay-<version>.dmg` (or `dist/Relay-<version>-adhoc.dmg` when `RELAY_SIGN_IDENTITY=-`).

- [ ] **Step 1: Write the signing identity script**

`scripts/make-signing-identity.sh`:

```bash
#!/bin/bash
# One-time setup: creates the free "Relay Self-Signed" code-signing certificate in your login keychain.
# Every release signed with it keeps users' permissions across updates. Back it up (see RELEASING.md).
set -euo pipefail
NAME="Relay Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
    echo "Already set up: $NAME"
    exit 0
fi
if security find-certificate -c "$NAME" "$KEYCHAIN" > /dev/null 2>&1; then
    echo "A certificate named \"$NAME\" exists but isn't usable for code signing." >&2
    echo "Open Keychain Access, check it (and its private key), and remove or fix it yourself first." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# macOS's own LibreSSL writes a PKCS#12 file that `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2> /dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/relay.p12" -passout "pass:$PASS"
security import "$TMP/relay.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "macOS will now ask for your password to trust the certificate for code signing."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
security find-identity -v -p codesigning
```

Run `chmod +x scripts/make-signing-identity.sh`. Do **not** run it during implementation: it changes the user's keychain and asks for their password (the user runs it once, per RELEASING.md).

- [ ] **Step 2: Write `First launch.txt`**

`Resources/First launch.txt`:

```text
Installing Relay

1. Drag Relay onto the Applications folder, then open Relay from Applications.

2. macOS says it can't verify the developer, because Relay is free and not signed by Apple.
   Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to Relay.
   You only need to do this once.

3. Relay appears in the menu bar at the top right. A welcome window explains the rest.

Requirements: a Mac with Apple Silicon and macOS 26 or later.
Claude Code is optional; it's only needed for "tell Claude to..." commands.
```

- [ ] **Step 3: Write the release script**

`scripts/make-release.sh`:

```bash
#!/bin/bash
# Builds a signed, portability-checked Relay DMG for GitHub Releases. See RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Relay Self-Signed"
IDENTITY="${RELAY_SIGN_IDENTITY:-$NAME}"
SUFFIX=""

if [ "$IDENTITY" = "-" ]; then
    echo "WARNING: ad-hoc signed test build. Permissions won't survive updates; don't publish this DMG." >&2
    SUFFIX="-adhoc"
elif ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "No \"$IDENTITY\" code-signing certificate. Run scripts/make-signing-identity.sh first." >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must look like 1.2.3 (found \"$VERSION\")." >&2
    exit 1
fi
DMG="dist/Relay-$VERSION$SUFFIX.dmg"
if [ -e "$DMG" ]; then
    echo "$DMG already exists. Bump VERSION, or move the old DMG away yourself." >&2
    exit 1
fi

RELAY_VERSION="$VERSION" RELAY_SIGN_IDENTITY="$IDENTITY" scripts/make-app.sh
scripts/check-portable.sh build/Relay.app

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto build/Relay.app "$STAGE/Relay.app"
ln -s /Applications "$STAGE/Applications"
cp "Resources/First launch.txt" "$STAGE/"
mkdir -p dist
hdiutil create -volname "Relay" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
echo "Built $DMG"
shasum -a 256 "$DMG"
```

Run `chmod +x scripts/make-release.sh`.

- [ ] **Step 4: Makefile and .gitignore**

In `Makefile`, add `release` to `.PHONY` and add:

```make
release:
	scripts/make-release.sh
```

In `.gitignore`, under `# Build output`, add a line `dist/`.

- [ ] **Step 5: Verify the missing-certificate path (if the certificate isn't set up yet)**

Run: `security find-identity -v -p codesigning | grep -c "Relay Self-Signed"; make release; echo "exit $?"`
Expected, when the count is 0: "No "Relay Self-Signed" code-signing certificate. Run scripts/make-signing-identity.sh first." and a non-zero exit. (If the count is 1, skip to Step 6 without the override and expect `dist/Relay-0.1.0.dmg`.)

- [ ] **Step 6: Verify the whole pipeline with an ad-hoc test build**

Run: `RELAY_SIGN_IDENTITY=- scripts/make-release.sh 2>&1 | tail -6`
Expected: the WARNING line, "Portability check: ok", "Built dist/Relay-0.1.0-adhoc.dmg" and a SHA-256 line.

Then run: `hdiutil attach -nobrowse -readonly dist/Relay-0.1.0-adhoc.dmg -mountpoint "$PWD/.superpowers/dmg" -quiet && ls -la .superpowers/dmg && codesign --verify --strict .superpowers/dmg/Relay.app && echo signature-ok; hdiutil detach .superpowers/dmg -quiet`
Expected: `Applications -> /Applications`, `First launch.txt`, `Relay.app`, then `signature-ok`.

Then run it again: `RELAY_SIGN_IDENTITY=- scripts/make-release.sh; echo "exit $?"`
Expected: "dist/Relay-0.1.0-adhoc.dmg already exists…" and a non-zero exit (nothing overwritten).

- [ ] **Step 7: Commit**

```bash
git add scripts/make-signing-identity.sh scripts/make-release.sh "Resources/First launch.txt" Makefile .gitignore
git commit -m "Add the signing identity script and make release with a DMG"
```

---

### Task 10: README, RELEASING and the manual checklist

**Files:**
- Create: `README.md`
- Create: `RELEASING.md`
- Modify: `docs/manual-checklist.md`

**Interfaces:**
- Consumes: everything above (names of scripts, settings, menu items).

- [ ] **Step 1: Write README.md**

`README.md`:

````markdown
# Relay

Relay is a small menu-bar voice assistant for the Mac. Press a hotkey (⌥Space by default), say what you want,
and press it again. Speech is turned into text on your Mac, and Relay opens apps, searches the web, controls
volume and media, handles windows and files, types for you, adds notes, reminders and timers, and can drive
[Claude Code](https://claude.com/product/claude-code). It never deletes, overwrites or force-quits anything.

## Requirements

- A Mac with Apple Silicon and macOS 26 or later
- About 700 MB free for the speech-routing model, downloaded once on first launch
- Optional: Claude Code, for "tell Claude to…" commands

## Install

1. Download `Relay-<version>.dmg` from the latest GitHub release and open it.
2. Drag **Relay** onto **Applications**, then open Relay from Applications.
3. macOS says it can't verify the developer, because Relay is free and not signed by Apple. Open
   **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Relay. This is
   needed once.
4. A welcome window walks you through the hotkey, permissions and a first command.

## Permissions

| Permission | Why | When it's asked |
|---|---|---|
| Microphone | to hear you, only between your two hotkey presses | first launch |
| Speech Recognition | to turn speech into text on this Mac | first launch |
| Accessibility | typing, window commands, brightness and media keys | first time you use one |
| Automation | dark mode (System Events), Finder folders, Apple Notes | first time you use one |
| Screen Recording | screenshots | first screenshot |
| Reminders | adding reminders | first reminder |

## Updating

Relay checks GitHub once a day and shows **Update available** in its menu when a new version is out (turn
this off in Settings). Download the new DMG and drag Relay into Applications, replacing the old one. Your
permissions stay.

## Things to say

- **Apps and web:** "open Safari", "quit TextEdit", "hide this app", "google mechanical keyboards"
- **Mac:** "set volume to 40 percent", "mute", "switch to dark mode", "lock my Mac", "keyboard light to 30 percent", "next song"
- **Windows and files:** "minimize this window", "close the tab", "make a new folder called invoices", "find my tax return"
- **Screenshots:** "take a screenshot", "screenshot this window", "screenshot an area", "copy a screenshot"
- **Typing and capture:** "type see you soon.", "note that the car needs servicing", "remind me to call mum at 5pm", "set a pasta timer for 9 minutes"
- **Claude Code:** choose a project from the menu, then "tell Claude to add a README", "start a new Claude session"

## Brightness and Focus

macOS has no public API for screen brightness or Do Not Disturb, so Relay uses three small shortcuts you build
once in the Shortcuts app. Relay shows the steps the first time you ask; they're also in
[docs/shortcuts-setup.md](docs/shortcuts-setup.md).

## Uninstall

1. Quit Relay (menu → Quit Relay) and drag it from Applications to the Trash.
2. Optionally remove its data and permissions:

   ```bash
   rm -r ~/Library/Application\ Support/Relay
   rm -r ~/Library/Application\ Support/FluidUse/Models/laya-coreml
   defaults delete dev.relay.Relay
   tccutil reset All dev.relay.Relay
   ```

3. Relay's "Relay" note in Apple Notes and any reminders it added are yours to keep or delete.

## Building from source

Needs the Command Line Tools (`xcode-select --install`).

```bash
make app     # build/Relay.app, locally signed
make run     # build and open it
make test    # unit tests
```

Releases are described in [RELEASING.md](RELEASING.md).
````

- [ ] **Step 2: Write RELEASING.md**

`RELEASING.md`:

````markdown
# Releasing Relay

## Once

1. Create the signing certificate:

   ```bash
   scripts/make-signing-identity.sh
   ```

   It asks for your password once. The first release may also ask whether `codesign` can use the key:
   choose **Always Allow**.
2. **Back it up.** In Keychain Access, find "Relay Self-Signed" under My Certificates, right-click →
   Export, and save the `.p12` somewhere safe. Every release must be signed with this certificate: a new one
   makes every user grant permissions again.
3. Set the repository in `Sources/RelayApp/ReleaseInfo.swift`, e.g. `static let repository = "you/relay"`.
   While it's empty the update check is off.

## Each release

1. Put the new version in `VERSION` (e.g. `0.2.0`) and commit.
2. Build:

   ```bash
   make release
   ```

   This signs Relay, runs the portability self-check with `.build` hidden, and writes
   `dist/Relay-<version>.dmg` plus its SHA-256. It refuses to overwrite an existing DMG.
3. Publish (tags are `vX.Y.Z`):

   ```bash
   gh release create v0.2.0 dist/Relay-0.2.0.dmg --title "Relay 0.2.0" --notes "What's new… SHA-256: <checksum>"
   ```

For a local test of the pipeline without the certificate: `RELAY_SIGN_IDENTITY=- scripts/make-release.sh`
(writes a `-adhoc` DMG; don't publish it).
````

- [ ] **Step 3: Update the manual checklist**

In `docs/manual-checklist.md`, replace the line `- [ ] Settings…: change the hotkey; the new hotkey works and the old one doesn't` with:

```markdown
- [ ] Settings…: click the hotkey, press ⌃⌘R: the new hotkey works and ⌥Space doesn't
- [ ] Settings…: click the hotkey, press R alone: "Add ⌘, ⌥, ⌃ or ⇧"; press Esc: recording stops and the old hotkey still works
- [ ] Settings…: click the hotkey, press a shortcut another app holds (e.g. ⌘Space if Spotlight uses it): "That shortcut is taken, so try another" or it registers but never fires — either way, set it back and the old one works
- [ ] Settings…: click the hotkey, then close Settings without pressing anything: the hotkey still works
- [ ] After updating from a build that used KeyboardShortcuts: the hotkey you had before still works
```

and append at the end:

```markdown

## Installing (end users)

- [ ] `make release` (with the certificate set up) builds `dist/Relay-<version>.dmg` and prints "Portability check: ok"
- [ ] In a new macOS user account: open the DMG, drag Relay to Applications, open it, click Open Anyway in Privacy & Security, and Relay starts
- [ ] The welcome window appears once: step 1 shows the hotkey recorder; step 2 shows Microphone/Speech rows (Allow works, ✓ appears) and the Laya download progress then "Ready ✓"; step 3 shows whether Claude Code was found
- [ ] Close the welcome window at step 1, relaunch: it doesn't come back; menu → Welcome… opens it at step 1
- [ ] Bump VERSION, `make release`, install the new DMG over the old app: Microphone, Speech and Accessibility are still granted (no prompts)
- [ ] With `ReleaseInfo.repository` set to a repo whose latest release is newer: Settings → Check now shows "Update available: v…", and the menu shows "Update available: v…" which opens the release page
- [ ] Turn off "Check for updates automatically": no check happens on the next launch (Settings → Check now still works)
- [ ] Settings shows "Relay <version> (build N)" at the bottom
```

- [ ] **Step 4: Verify the docs reference real things**

Run: `ls scripts/make-signing-identity.sh scripts/make-release.sh scripts/check-portable.sh docs/shortcuts-setup.md Sources/RelayApp/ReleaseInfo.swift && grep -c "Welcome…" Sources/RelayApp/MenuContent.swift`
Expected: all five paths listed, then `1`.

- [ ] **Step 5: Run the whole suite and routing, then commit**

Run: `make test > .superpowers/t10.log 2>&1; tail -5 .superpowers/t10.log; make test-routing 2>&1 | tail -3`
Expected: all tests pass; routing 64/64.

```bash
git add README.md RELEASING.md docs/manual-checklist.md
git commit -m "Add README, release guide and install checks"
```
