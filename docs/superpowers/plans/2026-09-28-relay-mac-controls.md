# Relay Sub-project A (Rule Routing + Mac & Media Controls) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relay understands nine new spoken commands through a keyword rule table and carries them out with system APIs: volume, brightness, dark mode, Do Not Disturb, lock, screenshot, and play/pause, next and previous.

**Architecture:**
- **Routing:** a `CommandRules` table in `Routing` runs after `SessionResetRule` and before the Laya gate.
- **Details:** pure parsers in `Extraction` (`LevelParser`, `SwitchParser`) read levels and on/off.
- **Actions:** a new UI-free `SystemControls` module carries them out behind the `SystemControlling` protocol. It uses CoreAudio, key events, AppleScript, `screencapture`, and a Shortcuts bridge for brightness and Focus.
- **State and UI:** `AssistantCore` maps intents to calls and messages. `RelayApp` adds a level bar to the pill, the shortcut setup steps to the panel, and the new permission links.

**Tech Stack:** Swift 6, macOS 26, Swift Testing, CoreAudio/AudioToolbox, ApplicationServices (Accessibility), CoreGraphics, NSAppleScript, `/usr/bin/shortcuts`, `/usr/sbin/screencapture`. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-28-relay-mac-controls-design.md`

## Global Constraints

- Branch `relay-v1`; `platforms: [.macOS("26.0")]`; Swift 6 language mode; no new package dependencies and no model downloads.
- Run tests through `make test` / `make test FILTER=<name>` (Command Line Tools flags). `make test-routing` must stay at `minimumAccuracy` 1.0.
- Non-destructive only: nothing is deleted, overwritten or force-quit.
- Routing order: `SessionResetRule` → `CommandRules` → Laya gate + the unchanged 3-way Laya choice. The Laya choice question does not change.
- Shortcut names, exactly: `Relay Brightness` (input: a fraction such as `0.70`), `Relay Focus On`, `Relay Focus Off` (no input).
- Volume step 10; "a bit"/"a little"/"slightly" step 6; brightness relative is 2 key presses (1 for a small step).
- User-facing messages use the exact strings in the tasks (from spec §5); tests compare them.
- End every commit message with: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

## Review Focus

1. **The output device has no volume control** (HDMI, some USB interfaces). Expected: "This audio device doesn't allow volume control." with no crash. Test in Task 5; the CoreAudio side is checked by hand.
2. **A bridge shortcut is deleted or renamed after Relay cached the list.** Expected: `shortcuts run` exits non-zero and the user sees "The Relay Brightness shortcut failed: …", not a hang. Test in Task 3.
3. **Permission is granted after a denial.** Expected: the next spoken command works without relaunching Relay, and the stale permission prompt clears when listening starts. Test in Task 5.
4. **Rule collisions with non-device commands.** "search for sound effects", "tell Claude to mute the tests", "find my resume file", "my brother is visiting next week", "unlock" must not trigger device actions. Tests in Task 2.
5. **Spoken numbers and out-of-range levels.** "forty five percent" is 45, "volume to 150" is clamped to 100, "one hundred" is 100. Tests in Task 1.

---

### Task 1: Level and switch parsers

**Files:**
- Create: `Sources/Extraction/LevelParser.swift`
- Create: `Sources/Extraction/SwitchParser.swift`
- Test: `Tests/ExtractionTests/LevelParserTests.swift`
- Test: `Tests/ExtractionTests/SwitchParserTests.swift`

**Interfaces:**
- Consumes: `TextNormalizer.normalize` (existing).
- Produces:
  - `public enum LevelCommand: Equatable, Sendable { case set(Int), up(Int), down(Int), mute, unmute }`
  - `LevelParser.parse(_ transcript: String) -> LevelCommand?`
  - `public enum SwitchCommand: Equatable, Sendable { case on, off, toggle }`
  - `SwitchParser.parse(_:) -> SwitchCommand`
  - `SwitchParser.darkMode(_:) -> SwitchCommand`
  - `SwitchParser.focusOn(_:) -> Bool`

- [ ] **Step 1: Write the failing tests**

`Tests/ExtractionTests/LevelParserTests.swift`:
```swift
import Testing
@testable import Extraction

@Test(arguments: [
    ("set volume to 40 percent", LevelCommand.set(40)),
    ("volume 40%", .set(40)),
    ("brightness to forty five percent", .set(45)),
    ("set the volume to one hundred", .set(100)),
    ("volume to 150", .set(100)),
    ("half volume", .set(50)),
    ("brightness all the way up", .set(100)),
    ("volume to max", .set(100)),
    ("turn the volume all the way down", .set(0)),
])
func absoluteLevels(_ transcript: String, _ expected: LevelCommand) {
    #expect(LevelParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("turn the volume up", LevelCommand.up(10)),
    ("crank up the volume", .up(10)),
    ("it's too quiet", .up(10)),
    ("the screen is too dark", .up(10)),
    ("a bit louder", .up(6)),
    ("make it slightly brighter", .up(6)),
    ("it's too loud, bring it down a bit", .down(6)),
    ("lower the sound", .down(10)),
    ("dim the display", .down(10)),
    ("the screen is too bright", .down(10)),
])
func relativeLevels(_ transcript: String, _ expected: LevelCommand) {
    #expect(LevelParser.parse(transcript) == expected)
}

@Test func muteBeatsDirectionWords() {
    #expect(LevelParser.parse("mute the sound") == .mute)
    #expect(LevelParser.parse("unmute my mac") == .unmute)
    #expect(LevelParser.parse("unmute and turn it up") == .unmute)
}

@Test func unknownLevelIsNil() {
    #expect(LevelParser.parse("volume banana") == nil)
    #expect(LevelParser.parse("brightness") == nil)
}
```

`Tests/ExtractionTests/SwitchParserTests.swift`:
```swift
import Testing
@testable import Extraction

@Test func genericSwitchWords() {
    #expect(SwitchParser.parse("turn on the thing") == .on)
    #expect(SwitchParser.parse("switch it off") == .off)
    #expect(SwitchParser.parse("enable it") == .on)
    #expect(SwitchParser.parse("dark mode") == .toggle)
}

@Test(arguments: [
    ("switch to dark mode", SwitchCommand.on),
    ("turn dark mode off", .off),
    ("dark mode", .toggle),
    ("switch to light mode", .off),
    ("turn on light mode", .off),
    ("light mode please", .off),
    ("turn off light mode", .on),
])
func darkModeUnderstandsLightMode(_ transcript: String, _ expected: SwitchCommand) {
    #expect(SwitchParser.darkMode(transcript) == expected)
}

@Test(arguments: [
    ("turn on do not disturb", true),
    ("enable do not disturb for an hour", true),
    ("turn off do not disturb", false),
    ("stop do not disturb", false),
    ("i need to focus, silence notifications", true),
    ("turn off notifications", true),
    ("turn notifications back on", false),
])
func focusUnderstandsNotifications(_ transcript: String, _ expected: Bool) {
    #expect(SwitchParser.focusOn(transcript) == expected)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=ParserTests`
Expected: the build fails with `cannot find 'LevelParser' in scope`.

- [ ] **Step 3: Implement**

`Sources/Extraction/LevelParser.swift`:
```swift
import Foundation

public enum LevelCommand: Equatable, Sendable {
    case set(Int)
    case up(Int)
    case down(Int)
    case mute
    case unmute
}

/// Reads a volume or brightness request: "40 percent", "forty five", "half", "a bit louder", "mute".
public enum LevelParser {
    static let upWords = ["up", "louder", "brighter", "raise", "increase", "crank", "turn up", "too dark", "too quiet"]
    static let downWords = ["down", "quieter", "dimmer", "dim", "lower", "decrease", "reduce", "turn down",
                            "too loud", "too bright"]
    static let smallStepWords = ["a bit", "a little", "slightly"]
    static let maxWords = ["max", "maximum", "all the way up", "full"]
    static let minWords = ["min", "minimum", "all the way down"]

    public static func parse(_ transcript: String) -> LevelCommand? {
        let text = TextNormalizer.normalize(transcript)
        let padded = " \(text) "
        func has(_ phrases: [String]) -> Bool { phrases.contains { padded.contains(" \($0) ") } }

        if has(["unmute"]) { return .unmute }
        if has(["mute", "silence the sound"]) { return .mute }
        if let number = number(in: text) { return .set(min(100, max(0, number))) }
        if has(["half"]) { return .set(50) }
        if has(maxWords) { return .set(100) }
        if has(minWords) { return .set(0) }
        let step = has(smallStepWords) ? 6 : 10
        if has(downWords) { return .down(step) }
        if has(upWords) { return .up(step) }
        return nil
    }

    /// The first number in the text: digits ("40") or spelled out ("forty five", "one hundred").
    static func number(in text: String) -> Int? {
        let words = text.split(separator: " ").map(String.init)
        if let digits = words.first(where: { Int($0) != nil }) { return Int(digits) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let run = words[start..<start + length]
                for candidate in [run.joined(separator: " "), run.joined(separator: "-")] {
                    if let value = formatter.number(from: candidate)?.intValue, value >= 0 { return value }
                }
            }
        }
        return nil
    }
}
```

`Sources/Extraction/SwitchParser.swift`:
```swift
public enum SwitchCommand: Equatable, Sendable {
    case on
    case off
    case toggle
}

/// Reads on/off requests. `darkMode` and `focusOn` handle words that flip the meaning.
public enum SwitchParser {
    static let offWords = ["off", "disable", "stop", "turn off", "deactivate", "end"]
    static let onWords = ["on", "enable", "start", "turn on", "switch to", "activate"]

    public static func parse(_ transcript: String) -> SwitchCommand {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        if offWords.contains(where: { padded.contains(" \($0) ") }) { return .off }
        if onWords.contains(where: { padded.contains(" \($0) ") }) { return .on }
        return .toggle
    }

    /// "light mode" means dark mode off: "switch to light mode" → .off, "turn off light mode" → .on.
    public static func darkMode(_ transcript: String) -> SwitchCommand {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        let mentionsLight = padded.contains(" light mode ") || padded.contains(" light theme ")
        let base = parse(transcript)
        guard mentionsLight else { return base }
        return base == .off ? .on : .off
    }

    /// Whether Do Not Disturb should be on. Relay can't read Focus state, so a bare request means on,
    /// and "notifications" flips the meaning ("turn off notifications" → on).
    public static func focusOn(_ transcript: String) -> Bool {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        let aboutNotifications = padded.contains(" notifications ") || padded.contains(" notification ")
        switch parse(transcript) {
        case .toggle: return true
        case .on: return !aboutNotifications
        case .off: return aboutNotifications
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=ParserTests`
Expected: all parser tests pass. If `"one hundred"` fails because `NumberFormatter` rejects the spaced form, keep the hyphenated fallback that's already in the loop and check the other spellings. Don't hard-code number words.

- [ ] **Step 5: Commit**

```bash
git add Sources/Extraction Tests/ExtractionTests
git commit -m "Add level and switch parsers for device commands" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Command rule table and routing

**Files:**
- Create: `Sources/Routing/CommandRules.swift`
- Modify: `Sources/Routing/RoutingTypes.swift` (new `RoutedIntent` cases and display names)
- Modify: `Sources/Routing/LayaRouter.swift` (call the rules; `layaDescription` for the new cases)
- Modify: `Sources/AssistantCore/Assistant.swift` (temporary handling of the new cases, replaced in Task 5)
- Modify: `Tests/RoutingTests/phrases.json` (20 device phrases)
- Test: `Tests/RoutingTests/CommandRulesTests.swift`

**Interfaces:**
- Consumes: `RoutingDecision`, `SessionResetRule` (existing).
- Produces:
  - `RoutedIntent` cases `volume`, `brightness`, `darkMode`, `focus`, `lock`, `screenshot`, `mediaPlayPause`, `mediaNext`, `mediaPrevious`
  - `CommandRules.match(_ transcript: String) -> RoutedIntent?`

- [ ] **Step 1: Write the failing tests**

`Tests/RoutingTests/CommandRulesTests.swift`:
```swift
import Testing
@testable import Routing

@Test(arguments: [
    ("turn the volume up", RoutedIntent.volume),
    ("set volume to 40 percent", .volume),
    ("it's too loud, bring it down a bit", .volume),
    ("mute the sound", .volume),
    ("make the screen brighter", .brightness),
    ("dim the display", .brightness),
    ("switch to dark mode", .darkMode),
    ("turn on light mode", .darkMode),
    ("turn on do not disturb", .focus),
    ("i need to focus, silence notifications", .focus),
    ("lock my mac", .lock),
    ("take a screenshot", .screenshot),
    ("grab a screen capture", .screenshot),
    ("play some music", .mediaPlayPause),
    ("pause", .mediaPlayPause),
    ("stop the music", .mediaPlayPause),
    ("resume the song", .mediaPlayPause),
    ("next song", .mediaNext),
    ("skip this track", .mediaNext),
    ("go back to the previous song", .mediaPrevious),
    ("play that last track again", .mediaPrevious),
])
func deviceCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("crank up the volume", RoutedIntent.volume),
    ("lower the sound", .volume),
    ("unmute my mac", .volume),
    ("turn the brightness all the way up", .brightness),
    ("the screen is too bright", .brightness),
    ("turn dark mode off", .darkMode),
    ("enable do not disturb for an hour", .focus),
    ("lock this computer", .lock),
    ("screenshot the screen", .screenshot),
    ("hit play", .mediaPlayPause),
    ("pause the song please", .mediaPlayPause),
    ("skip to the next one", .mediaNext),
    ("previous song please", .mediaPrevious),
])
func heldOutDevicePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    "search for sound effects",
    "google how loud is a jet engine",
    "tell claude to mute the tests",
    "find my resume file",
    "my brother is visiting next week",
    "unlock the door",
    "open the music app",
    "open the budget spreadsheet",
    "quit chrome",
    "go into full screen mode",
    "remind me at 8pm to take my medicine",
    "i think it's going to rain",
])
func otherCommandsAreLeftToLaya(_ transcript: String) {
    #expect(CommandRules.match(transcript) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=CommandRulesTests`
Expected: the build fails with `cannot find 'CommandRules' in scope` (and `type 'RoutedIntent' has no member 'volume'`).

- [ ] **Step 3: Add the intents**

In `Sources/Routing/RoutingTypes.swift`, replace the `RoutedIntent` enum with:
```swift
public enum RoutedIntent: String, CaseIterable, Sendable, Codable {
    case openApp = "open_app"
    case webSearch = "web_search"
    case askClaude = "ask_claude"
    case newClaudeSession = "new_claude_session"
    case volume
    case brightness
    case darkMode = "dark_mode"
    case focus
    case lock
    case screenshot
    case mediaPlayPause = "media_play_pause"
    case mediaNext = "media_next"
    case mediaPrevious = "media_previous"

    /// Wording for messages like "Maybe open an app or search the web?".
    public var displayName: String {
        switch self {
        case .openApp: "open an app"
        case .webSearch: "search the web"
        case .askClaude: "ask Claude"
        case .newClaudeSession: "start a new Claude session"
        case .volume: "change the volume"
        case .brightness: "change the brightness"
        case .darkMode: "switch dark mode"
        case .focus: "change Do Not Disturb"
        case .lock: "lock the screen"
        case .screenshot: "take a screenshot"
        case .mediaPlayPause: "play or pause"
        case .mediaNext: "skip to the next track"
        case .mediaPrevious: "go to the previous track"
        }
    }
}
```

In `Sources/Routing/LayaRouter.swift`, replace the `layaDescription` extension body with:
```swift
extension RoutedIntent {
    /// Option descriptions shown to Laya. Only `choiceIntents` are ever offered; the rest come from rules.
    var layaDescription: String {
        switch self {
        case .openApp: "launch or switch to an application on the Mac"
        case .webSearch: "search the internet or look something up in the browser"
        case .askClaude: "send a coding task or question to Claude Code"
        case .newClaudeSession: "start a fresh Claude Code conversation"
        default: displayName
        }
    }
}
```

- [ ] **Step 4: Implement the rule table**

`Sources/Routing/CommandRules.swift`:
```swift
/// Ordered keyword rules for device commands, checked after `SessionResetRule` and before Laya.
/// Evidence (spec §2): rules + Laya routed 39/40 held-out phrases; Laya alone managed ~50% on many-way choices.
public enum CommandRules {
    struct Rule {
        let intent: RoutedIntent
        /// At least one must appear as whole words.
        let anyOf: [String]
        /// If non-empty, at least one must also appear.
        var alsoAnyOf: [String] = []
        /// If non-empty, the transcript must start with one of these.
        var startsWith: [String] = []
        /// None of these may appear.
        var noneOf: [String] = []
    }

    static let documentNouns = ["file", "files", "document", "pdf", "spreadsheet", "presentation", "report",
                                "agreement", "contract", "invoice"]
    static let webLeadIns = ["search", "google", "look up", "find out"]

    static let rules: [Rule] = [
        Rule(intent: .screenshot, anyOf: ["screenshot", "screen shot", "screen capture", "capture the screen"]),
        Rule(intent: .lock, anyOf: ["lock"]),
        Rule(intent: .darkMode, anyOf: ["dark mode", "light mode", "dark theme", "light theme", "appearance"]),
        Rule(intent: .focus, anyOf: ["do not disturb", "focus", "notifications", "silence my mac"]),
        Rule(intent: .brightness, anyOf: ["brightness", "brighter", "dimmer", "dim", "too bright", "too dark"]),
        Rule(intent: .volume, anyOf: ["volume", "louder", "quieter", "mute", "unmute", "too loud", "sound"]),
        Rule(intent: .mediaPrevious, anyOf: ["previous", "last track", "last song", "back a song", "back a track"]),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], startsWith: ["next", "skip"]),
        Rule(intent: .mediaNext, anyOf: ["next", "skip"], alsoAnyOf: ["song", "track", "one"]),
        Rule(intent: .mediaPlayPause,
             anyOf: ["play", "pause", "resume", "unpause", "stop the music", "stop playing", "stop the song"],
             noneOf: ["open", "launch"] + documentNouns),
    ]

    public static func match(_ transcript: String) -> RoutedIntent? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        let padded = " \(words) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        func starts(_ phrase: String) -> Bool { padded.hasPrefix(" \(phrase) ") }

        // Claude requests and web searches are Laya's, even when they mention device words.
        if has("claude") || webLeadIns.contains(where: starts) { return nil }

        return rules.first { rule in
            rule.anyOf.contains(where: has)
                && (rule.alsoAnyOf.isEmpty || rule.alsoAnyOf.contains(where: has))
                && (rule.startsWith.isEmpty || rule.startsWith.contains(where: starts))
                && !rule.noneOf.contains(where: has)
        }?.intent
    }
}
```

- [ ] **Step 5: Run the rule tests to verify they pass**

Run: `make test FILTER=CommandRulesTests`
Expected: the Routing target and the rule tests compile and pass. The whole-package build may still fail in `AssistantCore` because `Assistant.perform`'s switch isn't exhaustive yet; Step 6 fixes that.

- [ ] **Step 6: Wire the rules into routing, with temporary assistant handling**

In `Sources/Routing/LayaRouter.swift`, in `route(_:)`, directly after the `SessionResetRule` block, add:
```swift
        if let intent = CommandRules.match(transcript) {
            return RoutingDecision(outcome: .intent(intent), gateProbability: 1,
                                   choiceProbabilities: [intent: 1], stateWasTruncated: false)
        }
```

In `Sources/AssistantCore/Assistant.swift`, add this as the last case of the `switch intent` in `perform(_:_:)`. Task 5 replaces it:
```swift
        case .volume, .brightness, .darkMode, .focus, .lock, .screenshot, .mediaPlayPause, .mediaNext, .mediaPrevious:
            return Outcome("Relay can't do that yet.", .info)
```

- [ ] **Step 7: Add device phrases to the real-model routing set**

In `Tests/RoutingTests/phrases.json`, add these entries to the `phrases` array. Keep `minimumAccuracy` at 1.0:
```json
    {"text": "turn the volume up", "expected": "volume"},
    {"text": "set volume to 40 percent", "expected": "volume"},
    {"text": "it's too loud", "expected": "volume"},
    {"text": "mute", "expected": "volume"},
    {"text": "make the screen brighter", "expected": "brightness"},
    {"text": "brightness to 70 percent", "expected": "brightness"},
    {"text": "switch to dark mode", "expected": "dark_mode"},
    {"text": "turn on light mode", "expected": "dark_mode"},
    {"text": "turn on do not disturb", "expected": "focus"},
    {"text": "turn off do not disturb", "expected": "focus"},
    {"text": "lock my mac", "expected": "lock"},
    {"text": "lock the screen", "expected": "lock"},
    {"text": "take a screenshot", "expected": "screenshot"},
    {"text": "grab a screen capture", "expected": "screenshot"},
    {"text": "pause", "expected": "media_play_pause"},
    {"text": "play some music", "expected": "media_play_pause"},
    {"text": "next song", "expected": "media_next"},
    {"text": "skip this track", "expected": "media_next"},
    {"text": "previous track", "expected": "media_previous"},
    {"text": "go back to the previous song", "expected": "media_previous"},
```

- [ ] **Step 8: Run all tests and the routing baseline**

Run: `make test`
Expected: all tests pass (the earlier suite plus the new rule tests).

Run: `make test-routing`
Expected: `routing accuracy: 34/34 = 1.0` and a pass. The rules take the 20 new phrases before Laya, and Laya still gets the original 14.

- [ ] **Step 9: Commit**

```bash
git add Sources/Routing Sources/AssistantCore Tests/RoutingTests
git commit -m "Add keyword rule table for device commands ahead of Laya routing" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: SystemControls foundation (protocol, errors, Shortcuts bridge, screenshot naming)

**Files:**
- Modify: `Package.swift` (add the `SystemControls` and `SystemControlsTests` targets)
- Create: `Sources/SystemControls/SystemControlling.swift`
- Create: `Sources/SystemControls/CommandRunner.swift`
- Create: `Sources/SystemControls/ShortcutsBridge.swift`
- Create: `Sources/SystemControls/ScreenshotLocation.swift`
- Test: `Tests/SystemControlsTests/ShortcutsBridgeTests.swift`
- Test: `Tests/SystemControlsTests/ScreenshotLocationTests.swift`

**Interfaces:**
- Consumes: `SwitchCommand` (Task 1).
- Produces:
  - `public enum MediaKey: Sendable, Equatable { case playPause, next, previous }`
  - `public enum SystemControlError: Error, Equatable { noVolumeControl, shortcutMissing(String), shortcutFailed(String, reason: String), automationDenied, accessibilityDenied, screenRecordingDenied, failed(String) }`
  - `public protocol SystemControlling: Sendable` (signatures below)
  - `public struct CommandResult: Sendable, Equatable { status: Int32; stdout: String; stderr: String; init(...) }`
  - `public protocol CommandRunning: Sendable { func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult }`
  - `public struct ProcessRunner: CommandRunning`
  - `public actor ShortcutsBridge { static let brightness, focusOn, focusOff; init(runner:temporaryDirectory:); func run(_ name: String, input: String? = nil) async throws }`
  - `public enum ScreenshotLocation { static func folder(defaultsValue: String?, home: URL) -> URL; static func fileName(for date: Date) -> String }`

- [ ] **Step 1: Add the targets**

In `Package.swift`, add to `targets:`:
```swift
        .target(name: "SystemControls", dependencies: ["Extraction"]),
        .testTarget(name: "SystemControlsTests", dependencies: ["SystemControls", "Extraction"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/SystemControlsTests/ShortcutsBridgeTests.swift`:
```swift
import Foundation
import Testing
@testable import SystemControls

/// Records every call; `shortcuts list` prints `installed`; `shortcuts run` returns `runResult`.
actor FakeRunner: CommandRunning {
    var installed: [String]
    var runResult = CommandResult(status: 0, stdout: "", stderr: "")
    private(set) var calls: [[String]] = []
    private(set) var inputContents: [String] = []

    init(installed: [String]) { self.installed = installed }
    func setInstalled(_ names: [String]) { installed = names }
    func setRunResult(_ result: CommandResult) { runResult = result }

    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        calls.append([executable] + arguments)
        if arguments.first == "list" {
            return CommandResult(status: 0, stdout: installed.joined(separator: "\n") + "\n", stderr: "")
        }
        if let i = arguments.firstIndex(of: "-i") {
            inputContents.append(try String(contentsOfFile: arguments[i + 1], encoding: .utf8))
        }
        return runResult
    }
}

@Test func runsTheShortcutWithItsInputFile() async throws {
    let runner = FakeRunner(installed: ["Relay Brightness", "Other"])
    let bridge = ShortcutsBridge(runner: runner)
    try await bridge.run(ShortcutsBridge.brightness, input: "0.70")
    let calls = await runner.calls
    #expect(calls.first == ["/usr/bin/shortcuts", "list"])
    #expect(Array(calls.last!.prefix(3)) == ["/usr/bin/shortcuts", "run", "Relay Brightness"])
    #expect(calls.last!.contains("-i"))
    #expect(await runner.inputContents == ["0.70"])
}

@Test func runsWithoutInputWhenNoneIsGiven() async throws {
    let runner = FakeRunner(installed: ["Relay Focus On"])
    try await ShortcutsBridge(runner: runner).run(ShortcutsBridge.focusOn)
    #expect(await runner.calls.last == ["/usr/bin/shortcuts", "run", "Relay Focus On"])
}

@Test func installedListIsCachedAfterSuccess() async throws {
    let runner = FakeRunner(installed: ["Relay Focus On"])
    let bridge = ShortcutsBridge(runner: runner)
    try await bridge.run(ShortcutsBridge.focusOn)
    try await bridge.run(ShortcutsBridge.focusOn)
    #expect(await runner.calls.filter { $0.contains("list") }.count == 1)
}

@Test func missingShortcutIsReportedAndRecheckedNextTime() async throws {
    let runner = FakeRunner(installed: [])
    let bridge = ShortcutsBridge(runner: runner)
    await #expect(throws: SystemControlError.shortcutMissing("Relay Brightness")) {
        try await bridge.run(ShortcutsBridge.brightness, input: "0.50")
    }
    await runner.setInstalled(["Relay Brightness"])
    try await bridge.run(ShortcutsBridge.brightness, input: "0.50")
    #expect(await runner.calls.filter { $0.contains("list") }.count == 2)
}

@Test func failingShortcutReportsItsError() async throws {
    let runner = FakeRunner(installed: ["Relay Brightness"])
    await runner.setRunResult(CommandResult(status: 1, stdout: "", stderr: "Couldn't find shortcut\n"))
    await #expect(throws: SystemControlError.shortcutFailed("Relay Brightness", reason: "Couldn't find shortcut")) {
        try await ShortcutsBridge(runner: runner).run(ShortcutsBridge.brightness, input: "0.50")
    }
}
```

`Tests/SystemControlsTests/ScreenshotLocationTests.swift`:
```swift
import Foundation
import Testing
@testable import SystemControls

private let home = URL(fileURLWithPath: "/Users/test")

@Test func defaultsToDesktop() {
    #expect(ScreenshotLocation.folder(defaultsValue: nil, home: home).path == "/Users/test/Desktop")
    #expect(ScreenshotLocation.folder(defaultsValue: "  ", home: home).path == "/Users/test/Desktop")
}

@Test func usesTheConfiguredFolderAndExpandsTilde() {
    #expect(ScreenshotLocation.folder(defaultsValue: "/Volumes/Shots", home: home).path == "/Volumes/Shots")
    #expect(ScreenshotLocation.folder(defaultsValue: "~/Pictures/Screens", home: home).path == "/Users/test/Pictures/Screens")
}

@Test func fileNameMatchesMacOSStyle() {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 28
    components.hour = 11; components.minute = 48; components.second = 3
    let date = Calendar.current.date(from: components)!
    #expect(ScreenshotLocation.fileName(for: date) == "Screenshot 2026-09-28 at 11.48.03.png")
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test FILTER=SystemControlsTests`
Expected: the build fails with `cannot find type 'CommandRunning' in scope`. (If SwiftPM first reports the target as having no sources, create `Sources/SystemControls/SystemControlling.swift` containing only `import Foundation` and rerun to see the real failure.)

- [ ] **Step 4: Implement**

`Sources/SystemControls/SystemControlling.swift`:
```swift
import Extraction
import Foundation

public enum MediaKey: Sendable, Equatable {
    case playPause
    case next
    case previous
}

public enum SystemControlError: Error, Equatable {
    case noVolumeControl
    case shortcutMissing(String)
    case shortcutFailed(String, reason: String)
    case automationDenied
    case accessibilityDenied
    case screenRecordingDenied
    case failed(String)
}

/// Everything Relay can change on the Mac. A protocol so the assistant can be tested with a fake.
public protocol SystemControlling: Sendable {
    /// Current output volume, 0…100.
    func volume() async throws -> Int
    func setVolume(_ percent: Int) async throws
    func setMuted(_ muted: Bool) async throws
    /// Sets an exact brightness through the "Relay Brightness" shortcut.
    func setBrightness(percent: Int) async throws
    /// Presses the brightness keys; each press is about 1/16.
    func stepBrightness(up: Bool, presses: Int) async throws
    /// Turns Do Not Disturb on or off through the "Relay Focus On/Off" shortcuts.
    func setFocus(on: Bool) async throws
    func setDarkMode(_ mode: SwitchCommand) async throws
    func lockScreen() async throws
    func pressMediaKey(_ key: MediaKey) async throws
    /// Returns where the screenshot was saved.
    func takeScreenshot() async throws -> URL
}
```

`Sources/SystemControls/CommandRunner.swift`:
```swift
import Foundation

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs a command-line tool. A protocol so tests don't run real tools.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Drain stderr on another queue so neither pipe can fill up and block the tool.
                var errorData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outputData, as: UTF8.self),
                    stderr: String(decoding: errorData, as: UTF8.self)))
            }
        }
    }
}
```

`Sources/SystemControls/ShortcutsBridge.swift`:
```swift
import Foundation

/// Runs Relay's helper shortcuts with `/usr/bin/shortcuts`. macOS has no public API for brightness or
/// Focus; the Shortcuts app's own "Set Brightness"/"Set Focus" actions are the supported route.
public actor ShortcutsBridge {
    public static let brightness = "Relay Brightness"
    public static let focusOn = "Relay Focus On"
    public static let focusOff = "Relay Focus Off"

    private let runner: any CommandRunning
    private let temporaryDirectory: URL
    private var installed: Set<String> = []

    public init(runner: any CommandRunning = ProcessRunner(),
                temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.runner = runner
        self.temporaryDirectory = temporaryDirectory
    }

    /// Runs `name`, passing `input` through a temporary text file (the CLI only takes input files).
    public func run(_ name: String, input: String? = nil) async throws {
        try await ensureInstalled(name)
        var arguments = ["run", name]
        var inputFile: URL?
        if let input {
            let file = temporaryDirectory.appendingPathComponent("relay-shortcut-\(UUID().uuidString).txt")
            try input.write(to: file, atomically: true, encoding: .utf8)
            arguments += ["-i", file.path]
            inputFile = file
        }
        let result: CommandResult
        do {
            result = try await runner.run("/usr/bin/shortcuts", arguments)
        } catch {
            if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
            throw SystemControlError.shortcutFailed(name, reason: error.localizedDescription)
        }
        if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.shortcutFailed(name, reason: reason.isEmpty ? "exit \(result.status)" : reason)
        }
    }

    private func ensureInstalled(_ name: String) async throws {
        if installed.contains(name) { return }
        let list = try await runner.run("/usr/bin/shortcuts", ["list"])
        installed = Set(list.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        guard installed.contains(name) else { throw SystemControlError.shortcutMissing(name) }
    }
}
```

`Sources/SystemControls/ScreenshotLocation.swift`:
```swift
import Foundation

/// Where and under what name screenshots are saved, matching macOS's own screenshot tool.
public enum ScreenshotLocation {
    /// `defaultsValue` is `com.apple.screencapture`'s `location`; unset or blank means the Desktop.
    public static func folder(defaultsValue: String?, home: URL) -> URL {
        guard let value = defaultsValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return home.appendingPathComponent("Desktop")
        }
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home.appendingPathComponent(String(value.dropFirst(2))) }
        return URL(fileURLWithPath: value)
    }

    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=SystemControlsTests`
Expected: all 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SystemControls Tests/SystemControlsTests
git commit -m "Add SystemControls protocol, Shortcuts bridge and screenshot naming" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Real Mac implementation

**Files:**
- Create: `Sources/SystemControls/CoreAudioVolume.swift`
- Create: `Sources/SystemControls/KeyEvents.swift`
- Create: `Sources/SystemControls/Permissions.swift`
- Create: `Sources/SystemControls/AppearanceScript.swift`
- Create: `Sources/SystemControls/MacSystemControls.swift`
- Test: `Tests/SystemControlsTests/MacSystemControlsTests.swift`

**Interfaces:**
- Consumes: Task 3's `SystemControlling`, `SystemControlError`, `ShortcutsBridge`, `CommandRunning`, `ProcessRunner`, `ScreenshotLocation`, `MediaKey`; Task 1's `SwitchCommand`.
- Produces: `public final class MacSystemControls: SystemControlling { init(shortcuts: ShortcutsBridge = ShortcutsBridge(), runner: any CommandRunning = ProcessRunner()) }`

- [ ] **Step 1: Write the failing tests**

`Tests/SystemControlsTests/MacSystemControlsTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=MacSystemControlsTests`
Expected: the build fails with `cannot find 'AppearanceScript' in scope`.

- [ ] **Step 3: Implement**

`Sources/SystemControls/CoreAudioVolume.swift`:
```swift
import AudioToolbox
import CoreAudio

/// Volume and mute on the default output device.
enum CoreAudioVolume {
    static func volume() throws -> Int {
        let device = try defaultOutputDevice()
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { throw SystemControlError.noVolumeControl }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't read the volume (\(status))") }
        return Int((value * 100).rounded())
    }

    static func setVolume(_ percent: Int) throws {
        let device = try defaultOutputDevice()
        var address = volumeAddress
        try requireSettable(device, &address)
        var value = Float32(min(100, max(0, percent))) / 100
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't set the volume (\(status))") }
    }

    static func setMuted(_ muted: Bool) throws {
        let device = try defaultOutputDevice()
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        try requireSettable(device, &address)
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't change mute (\(status))") }
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { throw SystemControlError.failed("no audio output device") }
        return device
    }

    private static func requireSettable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) throws {
        guard AudioObjectHasProperty(device, &address) else { throw SystemControlError.noVolumeControl }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            throw SystemControlError.noVolumeControl
        }
    }
}
```

`Sources/SystemControls/KeyEvents.swift`:
```swift
import AppKit

/// Presses system keys the way the keyboard does. Posting events requires Accessibility permission.
enum KeyEvents {
    // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
    static let brightnessUp: Int32 = 2
    static let brightnessDown: Int32 = 3

    static func code(for key: MediaKey) -> Int32 {
        switch key {
        case .playPause: 16 // NX_KEYTYPE_PLAY
        case .next: 17      // NX_KEYTYPE_NEXT
        case .previous: 18  // NX_KEYTYPE_PREVIOUS
        }
    }

    /// Posts a media or brightness key press (down, then up) as a system-defined event.
    @MainActor static func pressSystemKey(_ code: Int32) {
        for isDown in [true, false] {
            let state: Int32 = isDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: Int((code << 16) | (state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// ⌃⌘Q, the system Lock Screen shortcut.
    @MainActor static func pressLockShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 12 /* kVK_ANSI_Q */, keyDown: isDown)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }
}
```

`Sources/SystemControls/Permissions.swift`:
```swift
import ApplicationServices
import CoreGraphics

/// Permission checks, run each time so a newly granted permission works without relaunching Relay.
enum Permissions {
    /// Shows the system Accessibility prompt the first time; throws until the user allows Relay.
    static func requireAccessibility() throws {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw SystemControlError.accessibilityDenied }
    }

    static func requireScreenRecording() throws {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
        throw SystemControlError.screenRecordingDenied
    }
}
```

`Sources/SystemControls/AppearanceScript.swift`:
```swift
import Extraction
import Foundation

/// Switches dark mode through System Events (needs Automation permission for System Events).
enum AppearanceScript {
    static func source(for mode: SwitchCommand) -> String {
        let value = switch mode {
        case .on: "true"
        case .off: "false"
        case .toggle: "not dark mode"
        }
        return "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)"
    }

    @MainActor static func run(_ mode: SwitchCommand) throws {
        var error: NSDictionary?
        NSAppleScript(source: source(for: mode))?.executeAndReturnError(&error)
        guard let error else { return }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 { throw SystemControlError.automationDenied } // errAEEventNotPermitted
        throw SystemControlError.failed(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)")
    }
}
```

`Sources/SystemControls/MacSystemControls.swift`:
```swift
import Extraction
import Foundation

/// The real implementation: CoreAudio, key events, AppleScript, `screencapture` and the Shortcuts bridge.
public final class MacSystemControls: SystemControlling {
    private let shortcuts: ShortcutsBridge
    private let runner: any CommandRunning

    public init(shortcuts: ShortcutsBridge = ShortcutsBridge(), runner: any CommandRunning = ProcessRunner()) {
        self.shortcuts = shortcuts
        self.runner = runner
    }

    static func brightnessInput(percent: Int) -> String {
        String(format: "%.2f", Double(min(100, max(0, percent))) / 100)
    }

    public func volume() async throws -> Int { try CoreAudioVolume.volume() }
    public func setVolume(_ percent: Int) async throws { try CoreAudioVolume.setVolume(percent) }
    public func setMuted(_ muted: Bool) async throws { try CoreAudioVolume.setMuted(muted) }

    public func setBrightness(percent: Int) async throws {
        try await shortcuts.run(ShortcutsBridge.brightness, input: Self.brightnessInput(percent: percent))
    }

    public func stepBrightness(up: Bool, presses: Int) async throws {
        try Permissions.requireAccessibility()
        let code = up ? KeyEvents.brightnessUp : KeyEvents.brightnessDown
        await MainActor.run {
            for _ in 0..<presses { KeyEvents.pressSystemKey(code) }
        }
    }

    public func setFocus(on: Bool) async throws {
        try await shortcuts.run(on ? ShortcutsBridge.focusOn : ShortcutsBridge.focusOff)
    }

    public func setDarkMode(_ mode: SwitchCommand) async throws {
        try await MainActor.run { try AppearanceScript.run(mode) }
    }

    public func lockScreen() async throws {
        try Permissions.requireAccessibility()
        await MainActor.run { KeyEvents.pressLockShortcut() }
    }

    public func pressMediaKey(_ key: MediaKey) async throws {
        try Permissions.requireAccessibility()
        await MainActor.run { KeyEvents.pressSystemKey(KeyEvents.code(for: key)) }
    }

    public func takeScreenshot() async throws -> URL {
        try Permissions.requireScreenRecording()
        let folder = ScreenshotLocation.folder(
            defaultsValue: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser)
        let file = folder.appendingPathComponent(ScreenshotLocation.fileName(for: Date()))
        let result = try await runner.run("/usr/sbin/screencapture", ["-x", file.path])
        guard result.status == 0, FileManager.default.fileExists(atPath: file.path) else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "screencapture exited \(result.status)" : reason)
        }
        return file
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=MacSystemControlsTests`
Expected: 3 tests pass; `readsTheRealOutputVolume` is skipped.

Run: `RELAY_SYSTEM_TESTS=1 make test FILTER=MacSystemControlsTests`
Expected: `readsTheRealOutputVolume` passes. If the Mac's current output device has no volume control, it fails with `noVolumeControl`; switch to the built-in speakers and rerun.

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemControls Tests/SystemControlsTests
git commit -m "Add real Mac system controls: CoreAudio, key events, AppleScript, screencapture" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Assistant handles the device commands

**Files:**
- Modify: `Package.swift` (`AssistantCore` and `AssistantCoreTests` depend on `SystemControls`)
- Modify: `Sources/AssistantCore/Assistant.swift`
- Modify: `Tests/AssistantCoreTests/Fakes.swift` (`FakeSystem`; `Harness` passes it)
- Modify: `Sources/RelayApp/AppController.swift` (pass `MacSystemControls()` so the app builds)
- Test: `Tests/AssistantCoreTests/SystemCommandTests.swift`

**Interfaces:**
- Consumes:
  - `LevelParser`, `LevelCommand`, `SwitchParser` (Task 1)
  - the new `RoutedIntent` cases (Task 2)
  - `SystemControlling`, `SystemControlError`, `MediaKey`, `MacSystemControls` (Tasks 3–4)
- Produces:
  - `AssistantDependencies.system: any SystemControlling`, added as the `system:` init parameter after `opener:`
  - `PermissionKind` cases `.accessibility`, `.screenRecording`, `.automation`
  - `Assistant.resultLevel: Double?`
  - `Assistant.missingShortcut: String?`

- [ ] **Step 1: Wire the dependency**

In `Package.swift`:
- change the `AssistantCore` target's dependencies to `["Extraction", "Actions", "Routing", "Capture", "Transcription", "SystemControls"]`
- add `"SystemControls"` to the `AssistantCoreTests` dependency list

- [ ] **Step 2: Write the fake and the failing tests**

In `Tests/AssistantCoreTests/Fakes.swift`, add `@testable import SystemControls` to the imports, then add this fake:
```swift
actor FakeSystem: SystemControlling {
    private(set) var calls: [String] = []
    var currentVolume = 50
    var failure: SystemControlError?

    func setCurrentVolume(_ value: Int) { currentVolume = value }
    func fail(with error: SystemControlError?) { failure = error }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func volume() throws -> Int { try record("volume()"); return currentVolume }
    func setVolume(_ percent: Int) throws { try record("setVolume(\(percent))"); currentVolume = percent }
    func setMuted(_ muted: Bool) throws { try record("setMuted(\(muted))") }
    func setBrightness(percent: Int) throws { try record("setBrightness(\(percent))") }
    func stepBrightness(up: Bool, presses: Int) throws { try record("stepBrightness(up: \(up), presses: \(presses))") }
    func setFocus(on: Bool) throws { try record("setFocus(\(on))") }
    func setDarkMode(_ mode: SwitchCommand) throws { try record("setDarkMode(\(mode))") }
    func lockScreen() throws { try record("lockScreen()") }
    func pressMediaKey(_ key: MediaKey) throws { try record("pressMediaKey(\(key))") }
    func takeScreenshot() throws -> URL {
        try record("takeScreenshot()")
        return URL(fileURLWithPath: "/Users/test/Desktop/Screenshot 2026-09-28 at 11.48.03.png")
    }
}
```

In `Harness`:
- add the property `let system = FakeSystem()` next to `let opener = FakeOpener()`
- in `init`, pass `system: system` to `AssistantDependencies(...)` directly after `opener: opener,`

`Tests/AssistantCoreTests/SystemCommandTests.swift`:
```swift
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
        (.screenRecordingDenied, .screenshot, "Relay needs Screen Recording permission to take screenshots.", .screenRecording),
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test FILTER=AssistantCoreTests`
Expected: the build fails with errors like `extra argument 'system' in call` and `value of type 'Assistant' has no member 'resultLevel'`.

- [ ] **Step 4: Implement in the assistant**

In `Sources/AssistantCore/Assistant.swift`:

1. Add `import SystemControls` to the imports.
2. Extend `PermissionKind`:
```swift
public enum PermissionKind: Sendable, Equatable {
    case microphone
    case speechRecognition
    case accessibility
    case screenRecording
    case automation
}
```
3. In `AssistantDependencies`, add the stored property `public var system: any SystemControlling` after `opener`. Add the init parameter `system: any SystemControlling` directly after `opener: any URLOpening`, and assign `self.system = system`.
4. Add observable state next to `resultKind`:
```swift
    /// 0…1 for results with a known level (volume, brightness set), shown as a bar in the pill.
    public private(set) var resultLevel: Double?
    /// The helper shortcut the user needs to set up, e.g. "Relay Brightness".
    public private(set) var missingShortcut: String?
```
5. In `hotkeyPressed()`'s `.idle` branch, in the block that sets `resultKind = nil`, also clear the stale prompts:
```swift
                resultLevel = nil
                missingShortcut = nil
                missingPermission = nil
```
6. Replace the temporary `case .volume, .brightness, … return Outcome("Relay can't do that yet.", .info)` from Task 2 with:
```swift
        case .volume:
            guard let command = LevelParser.parse(text) else {
                return Outcome("What volume? Try a percentage, like 40 percent.", .info)
            }
            return await control("change the volume") { try await self.changeVolume(command) }

        case .brightness:
            guard let command = LevelParser.parse(text), command != .mute, command != .unmute else {
                return Outcome("What brightness? Try a percentage, like 70 percent.", .info)
            }
            return await control("change the brightness") { try await self.changeBrightness(command) }

        case .darkMode:
            let mode = SwitchParser.darkMode(text)
            return await control("switch dark mode") {
                try await self.deps.system.setDarkMode(mode)
                let message = switch mode {
                case .on: "Dark mode on"
                case .off: "Dark mode off"
                case .toggle: "Switched appearance"
                }
                return Outcome(message, .success)
            }

        case .focus:
            let on = SwitchParser.focusOn(text)
            return await control("change Do Not Disturb") {
                try await self.deps.system.setFocus(on: on)
                return Outcome(on ? "Do Not Disturb on" : "Do Not Disturb off", .success)
            }

        case .lock:
            return await control("lock the screen") {
                try await self.deps.system.lockScreen()
                return Outcome("Locking…", .success)
            }

        case .screenshot:
            return await control("take a screenshot") {
                let file = try await self.deps.system.takeScreenshot()
                return Outcome("Screenshot saved to \(file.deletingLastPathComponent().lastPathComponent)", .success)
            }

        case .mediaPlayPause:
            return await control("play or pause") {
                try await self.deps.system.pressMediaKey(.playPause)
                return Outcome("Play/Pause", .success)
            }

        case .mediaNext:
            return await control("skip to the next track") {
                try await self.deps.system.pressMediaKey(.next)
                return Outcome("Next track", .success)
            }

        case .mediaPrevious:
            return await control("go to the previous track") {
                try await self.deps.system.pressMediaKey(.previous)
                return Outcome("Previous track", .success)
            }
```
7. Add these private helpers below `perform`:
```swift
    private func changeVolume(_ command: LevelCommand) async throws -> Outcome {
        let system = deps.system
        let level: Int
        switch command {
        case .mute:
            try await system.setMuted(true)
            return Outcome("Muted", .success)
        case .unmute:
            try await system.setMuted(false)
            resultLevel = Double(try await system.volume()) / 100
            return Outcome("Unmuted", .success)
        case .set(let percent):
            try await system.setVolume(percent)
            if percent > 0 { try await system.setMuted(false) }
            level = percent
        case .up(let step):
            level = min(100, try await system.volume() + step)
            try await system.setMuted(false)
            try await system.setVolume(level)
        case .down(let step):
            level = max(0, try await system.volume() - step)
            try await system.setVolume(level)
        }
        resultLevel = Double(level) / 100
        return Outcome("Volume \(level)%", .success)
    }

    private func changeBrightness(_ command: LevelCommand) async throws -> Outcome {
        switch command {
        case .set(let percent):
            try await deps.system.setBrightness(percent: percent)
            resultLevel = Double(percent) / 100
            return Outcome("Brightness \(percent)%", .success)
        case .up(let step), .down(let step):
            var up = false
            if case .up = command { up = true }
            try await deps.system.stepBrightness(up: up, presses: step <= 6 ? 1 : 2)
            return Outcome(up ? "Brighter" : "Dimmer", .success)
        case .mute, .unmute:
            return Outcome("What brightness? Try a percentage, like 70 percent.", .info)
        }
    }

    /// Runs a system action, turning its errors into the messages from spec §5.
    private func control(_ action: String, _ body: () async throws -> Outcome) async -> Outcome {
        do {
            return try await body()
        } catch let error as SystemControlError {
            switch error {
            case .noVolumeControl:
                return Outcome("This audio device doesn't allow volume control.", .problem)
            case .shortcutMissing(let name):
                missingShortcut = name
                let feature = name == ShortcutsBridge.brightness ? "Brightness" : "Do Not Disturb"
                return Outcome("\(feature) needs a one-time setup.", .info)
            case .shortcutFailed(let name, let reason):
                return Outcome("The \(name) shortcut failed: \(reason)", .problem)
            case .automationDenied:
                missingPermission = .automation
                return Outcome("Relay needs permission to control System Events for dark mode.", .problem)
            case .accessibilityDenied:
                missingPermission = .accessibility
                return Outcome("Relay needs Accessibility access to press keys for you.", .problem)
            case .screenRecordingDenied:
                missingPermission = .screenRecording
                return Outcome("Relay needs Screen Recording permission to take screenshots.", .problem)
            case .failed(let reason):
                return Outcome("Couldn't \(action): \(reason)", .problem)
            }
        } catch {
            return Outcome("Couldn't \(action): \(error.localizedDescription)", .problem)
        }
    }
```

In `Sources/RelayApp/AppController.swift`:
- add `import SystemControls`
- in the `AssistantDependencies(...)` call, add `system: MacSystemControls(),` directly after `opener: WorkspaceOpener(),`
- add `"SystemControls"` to the `RelayApp` target's dependencies in `Package.swift`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=AssistantCoreTests`
Expected: all AssistantCore tests pass, the earlier ones plus the 12 in `SystemCommandTests`.

Run: `make test`
Expected: the whole suite passes.

Run: `swift build`
Expected: `Build complete!`. `AppController` compiles, though `openPrivacySettings` doesn't yet handle the new `PermissionKind` cases correctly. If the compiler reports a non-exhaustive switch there, map every non-microphone case to `"Privacy_SpeechRecognition"` for now; Task 6 replaces it.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/AssistantCore Sources/RelayApp/AppController.swift Tests/AssistantCoreTests
git commit -m "Handle volume, brightness, dark mode, focus, lock, screenshot and media commands" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Pill level bar, shortcut setup, permission links and bundle

**Files:**
- Modify: `Sources/RelayApp/HUDView.swift` (level bar)
- Modify: `Sources/RelayApp/PanelView.swift` (shortcut setup section)
- Modify: `Sources/RelayApp/AppController.swift` (settings anchors, shortcut helpers, panel trigger)
- Modify: `Resources/Info.plist` (Automation usage text)
- Modify: `scripts/make-app.sh` (copy optional signed shortcuts)
- Create: `docs/shortcuts-setup.md`
- Modify: `docs/manual-checklist.md`

**Interfaces:**
- Consumes: `Assistant.resultLevel`, `Assistant.missingShortcut`, the new `PermissionKind` cases (Task 5); `ShortcutsBridge.brightness/focusOn/focusOff` (Task 3).
- Produces: UI only.

This task is UI glue, verified by the build and the manual checklist.

- [ ] **Step 1: Level bar in the pill**

In `Sources/RelayApp/HUDView.swift`, in the `.idle` case of `label`, replace the result text block with:
```swift
            case .idle:
                HStack(spacing: 10) {
                    Text(assistant.message ?? "")
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320, alignment: .leading)
                    if let level = assistant.resultLevel {
                        LevelBar(level: level)
                    }
                }
```
And add at the end of the file:
```swift
/// A small capsule that fills to the result level, like macOS's own volume overlay.
private struct LevelBar: View {
    let level: Double
    @State private var shown: Double = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.secondary.opacity(0.25))
            Capsule().fill(.primary).frame(width: 72 * shown)
        }
        .frame(width: 72, height: 6)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { shown = level } }
        .onChange(of: level) { _, new in withAnimation(.spring(duration: 0.5, bounce: 0.3)) { shown = new } }
    }
}
```

- [ ] **Step 2: Controller helpers**

In `Sources/RelayApp/AppController.swift`:

Replace `openPrivacySettings(for:)` with:
```swift
    func openPrivacySettings(for kind: PermissionKind) {
        let anchor = switch kind {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    /// A signed shortcut file bundled in Relay.app, if one was added to Resources/Shortcuts.
    func bundledShortcut(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    /// Opens a bundled shortcut in Shortcuts' import dialog, or the Shortcuts app so the user can build it.
    func setUpShortcut(named name: String) {
        if let file = bundledShortcut(named: name) {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
```

In `watchForPanelWorthyChanges()`:
- add `_ = assistant.missingShortcut` inside the tracking closure
- add `|| self.assistant.missingShortcut != nil` to the condition that shows the panel

- [ ] **Step 3: Shortcut setup section in the panel**

In `Sources/RelayApp/PanelView.swift`, directly after the permission `if … else if assistant.prepareFailed { … }` block, add:
```swift
            if let shortcut = assistant.missingShortcut {
                ShortcutSetupView(name: shortcut, isBundled: controller.bundledShortcut(named: shortcut) != nil) {
                    controller.setUpShortcut(named: shortcut)
                }
            }
```
And add at the end of the file:
```swift
/// Explains how to create one of Relay's helper shortcuts (one action each).
struct ShortcutSetupView: View {
    let name: String
    let isBundled: Bool
    let action: () -> Void

    private var steps: [String] {
        switch name {
        case "Relay Brightness":
            ["In Shortcuts, create a new shortcut named “Relay Brightness”.",
             "Add the “Set Brightness” action.",
             "Click its brightness value and choose “Shortcut Input”."]
        case "Relay Focus On":
            ["In Shortcuts, create a new shortcut named “Relay Focus On”.",
             "Add the “Set Focus” action and set it to turn Do Not Disturb On.",
             "Create “Relay Focus Off” the same way, turning Do Not Disturb Off."]
        default:
            ["In Shortcuts, create a new shortcut named “\(name)”.",
             "Add the “Set Focus” action and set it to turn Do Not Disturb Off.",
             "Create “Relay Focus On” the same way, turning Do Not Disturb On."]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One-time setup: \(name)").font(.headline)
            if isBundled {
                Text("Click Add Shortcut, then Add in the Shortcuts window.")
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
                Text("Then say the command again.").foregroundStyle(.secondary)
            }
            Button(isBundled ? "Add Shortcut" : "Open Shortcuts", action: action)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 4: Bundle files**

In `Resources/Info.plist`, add inside the `<dict>`:
```xml
    <key>NSAppleEventsUsageDescription</key>
    <string>Relay controls System Events to switch dark mode when you ask.</string>
```

In `scripts/make-app.sh`, directly before the `codesign --force` line, add:
```bash
# Optional signed helper shortcuts (see docs/shortcuts-setup.md).
if compgen -G "Resources/Shortcuts/*.shortcut" > /dev/null; then
    mkdir -p "$APP/Contents/Resources/Shortcuts"
    cp Resources/Shortcuts/*.shortcut "$APP/Contents/Resources/Shortcuts/"
fi
```

`docs/shortcuts-setup.md`:
```markdown
# Relay helper shortcuts

macOS has no public API for screen brightness or Do Not Disturb, so Relay uses three tiny shortcuts built
from the Shortcuts app's own actions. Relay shows these steps in its panel the first time you need them.

| Shortcut | Build it like this |
|---|---|
| **Relay Brightness** | New shortcut → add **Set Brightness** → click the brightness value → choose **Shortcut Input** |
| **Relay Focus On** | New shortcut → add **Set Focus** → set it to turn **Do Not Disturb On** |
| **Relay Focus Off** | New shortcut → add **Set Focus** → set it to turn **Do Not Disturb Off** |

The names must match exactly. Relay runs them with `shortcuts run "<name>"`; brightness is passed as a
fraction such as `0.70`.

**Optional one-click setup:** export each finished shortcut from the Shortcuts app (File → Export, "Anyone")
into `Resources/Shortcuts/<name>.shortcut`. `make app` then bundles them and Relay's panel offers
**Add Shortcut** instead of the steps.
```

- [ ] **Step 5: Update the manual checklist**

In `docs/manual-checklist.md`, add before the `decisions.jsonl` line:
```markdown
- [ ] "Set volume to 40 percent": the volume changes; the pill shows "Volume 40%" with the level bar filling to 40%
- [ ] "Turn the volume up" / "it's too loud" / "mute" / "unmute" each work and show the new level
- [ ] "Brightness to 70 percent" (first time): the panel shows the Relay Brightness setup steps; after building the shortcut, the command sets 70%
- [ ] "A bit brighter" / "dim the display": Relay asks for Accessibility once; after allowing, brightness steps up/down
- [ ] "Switch to dark mode" / "switch to light mode": Relay asks for Automation (System Events) once; appearance switches
- [ ] "Turn on do not disturb" / "turn off do not disturb": after building the Focus shortcuts, the Focus icon in Control Center changes
- [ ] "Lock my Mac": the screen locks immediately
- [ ] "Pause" / "next song" / "previous track" control Music, and also a playing YouTube tab
- [ ] "Take a screenshot": Relay asks for Screen Recording once (you may need to reopen Relay); the file appears in your screenshot folder and the pill names the folder
- [ ] After denying a permission and then allowing it in System Settings, the same spoken command works without relaunching (except Screen Recording, which macOS may require a relaunch for)
- [ ] "Tell Claude to mute the tests" goes to Claude, and "search for sound effects" opens a web search
```

- [ ] **Step 6: Build, test and bundle**

Run: `make test`
Expected: the whole suite passes.

Run: `make app`
Expected: it ends with `Built build/Relay.app`, and `codesign --verify` prints nothing.

Run: `plutil -p build/Relay.app/Contents/Info.plist | grep NSAppleEvents`
Expected: the Automation usage string is printed.

- [ ] **Step 7: Commit**

```bash
git add Sources/RelayApp Resources/Info.plist scripts/make-app.sh docs/shortcuts-setup.md docs/manual-checklist.md
git commit -m "Show device levels in the pill, guide shortcut setup, and link new permissions" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
