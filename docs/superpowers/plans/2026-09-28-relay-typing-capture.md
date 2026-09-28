# Relay Sub-project C (Typing and Quick Capture) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relay types dictated text into the app in front, adds lines to a running "Relay" note in Apple Notes, adds Apple Reminders (with alerts when a time is spoken), and runs named timers that fire even if Relay quits.

**Architecture:**
- **Routing:** C's rules go at the **top** of `CommandRules`.
- **Details:** pure parsers in `Extraction` (dictation, note, reminder, timer).
- **Actions:** a third protocol, `CaptureControlling`, in `SystemControls`, with a real `MacCaptureControls`:
  - pasteboard swap plus ⌘V for typing
  - `osascript` for Notes
  - EventKit for Reminders
  - a JSON timer store plus scheduled user notifications
- **Error change:** `automationDenied` gains the app's name.
- **Assistant and UI:** `AssistantCore` maps the intents and formats durations and times; `RelayApp` adds a live Timers section to the panel.

**Tech Stack:** Swift 6, macOS 26, Swift Testing, AppKit (NSPasteboard), EventKit, UserNotifications, NSDataDetector, `/usr/bin/osascript`. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-28-relay-typing-capture-design.md`

## Global Constraints

- Branch `relay-c-typing-capture`; macOS 26; Swift 6; no new dependencies.
- Run tests through `make test` / `make test FILTER=<name>`. `make test-routing` must stay at `minimumAccuracy` 1.0.
- **Non-destructive only:** notes are only added to (never edited or removed), reminders are only created, and the clipboard is restored only if nothing else changed it (`changeCount`).
- The note is named "Relay"; timers live in `~/Library/Application Support/Relay/timers.json`.
- Note text reaches AppleScript only as an argument, never inserted into script source.
- User-facing messages use the exact strings in the tasks (spec §4); tests compare them.
- End every commit message with: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

## Review Focus

1. **The clipboard changes between Relay's paste and its restore** (the user copies something). Expected: Relay leaves the new clipboard alone. Test in Task 3 (with a private pasteboard).
2. **Note text containing quotes, `<`, `&` or AppleScript-like text** ("say \"hi\" & quit"). Expected: saved literally, escaped as HTML, and never able to break or inject into the script. Tests in Task 3.
3. **A reminder time that has already passed today** ("at 3pm" at 4pm). Expected: tomorrow at 3 PM, not in the past. Test in Task 1.
4. **Several timers with the same name** ("pasta" twice). Expected: "pasta 2", and cancelling "pasta" cancels only the first. Tests in Tasks 3 and 5.
5. **`timers.json` corrupt, or deleted while Relay runs.** Expected: treated as no timers; Relay never crashes. Test in Task 3.

---

### Task 1: Parsers for dictation, notes, reminders and timers

**Files:**
- Create: `Sources/Extraction/DictationParser.swift`
- Create: `Sources/Extraction/NoteParser.swift`
- Create: `Sources/Extraction/ReminderParser.swift`
- Create: `Sources/Extraction/TimerParser.swift`
- Test: `Tests/ExtractionTests/CaptureParserTests.swift`

**Interfaces:**
- Consumes: `LeadIn.matchEnd(of:in:)`, `LeadIn.strip(_:phrases:)`, `LeadIn.courtesy`, `TextNormalizer.normalize` (existing).
- Produces:
  - `DictationParser.text(from:) -> String?`
  - `NoteParser.text(from:) -> String?`
  - `public struct ReminderRequest: Equatable, Sendable { title: String?; due: Date? }`
  - `ReminderParser.parse(_:now:calendar:) -> ReminderRequest`
  - `public struct TimerRequest: Equatable, Sendable { seconds: Int?; name: String? }`
  - `public enum TimerTarget: Equatable, Sendable { case all, named(String), unspecified }`
  - `TimerParser.parse(_:) -> TimerRequest`
  - `TimerParser.target(_:) -> TimerTarget`

- [ ] **Step 1: Write the failing tests**

`Tests/ExtractionTests/CaptureParserTests.swift`:
```swift
import Foundation
import Testing
@testable import Extraction

@Test(arguments: [
    ("type see you soon.", "see you soon."),
    ("Type: Hello, World!", "Hello, World!"),
    ("write thank you so much", "thank you so much"),
    ("write down my address", "my address"),
    ("type out I'm on my way", "I'm on my way"),
    ("dictate thanks, I'll review it today.", "thanks, I'll review it today."),
    ("please type hello", "hello"),
])
func dictationKeepsWordingAndPunctuation(_ transcript: String, _ expected: String) {
    #expect(DictationParser.text(from: transcript) == expected)
}

@Test func emptyDictationIsNil() {
    #expect(DictationParser.text(from: "type") == nil)
    #expect(DictationParser.text(from: "write:") == nil)
}

@Test(arguments: [
    ("note that the car needs servicing", "the car needs servicing"),
    ("take a note that the wifi password is on the fridge", "the wifi password is on the fridge"),
    ("note down buy milk and eggs", "buy milk and eggs"),
    ("add a note saying call the bank", "call the bank"),
    ("jot down this idea", "this idea"),
])
func noteTextDropsTheLeadIn(_ transcript: String, _ expected: String) {
    #expect(NoteParser.text(from: transcript) == expected)
}

@Test func emptyNoteIsNil() {
    #expect(NoteParser.text(from: "take a note") == nil)
}

// Reminders — "now" is fixed at 16:00 today in the Mac's calendar and time zone.
private let calendar = Calendar.current
private let now = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!

private func at(_ hour: Int, _ minute: Int = 0, daysFromNow days: Int = 0) -> Date {
    let day = calendar.date(byAdding: .day, value: days, to: now)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

@Test func reminderAtALaterTimeToday() {
    #expect(ReminderParser.parse("remind me to call mum at 5pm", now: now, calendar: calendar)
        == ReminderRequest(title: "call mum", due: at(17)))
}

@Test func reminderAtATimeAlreadyPassedMovesToTomorrow() {
    #expect(ReminderParser.parse("remind me at 3pm to call the bank", now: now, calendar: calendar)
        == ReminderRequest(title: "call the bank", due: at(15, daysFromNow: 1)))
}

@Test func reminderTomorrowAtNine() {
    #expect(ReminderParser.parse("remind me tomorrow at 9 to pay rent", now: now, calendar: calendar)
        == ReminderRequest(title: "pay rent", due: at(9, daysFromNow: 1)))
}

@Test func reminderInTwentyMinutes() {
    #expect(ReminderParser.parse("remind me to stretch in 20 minutes", now: now, calendar: calendar)
        == ReminderRequest(title: "stretch", due: now.addingTimeInterval(1200)))
    #expect(ReminderParser.parse("remind me in half an hour to check the oven", now: now, calendar: calendar)
        == ReminderRequest(title: "check the oven", due: now.addingTimeInterval(1800)))
}

@Test func reminderWithoutATime() {
    #expect(ReminderParser.parse("remind me to buy milk", now: now, calendar: calendar)
        == ReminderRequest(title: "buy milk", due: nil))
    #expect(ReminderParser.parse("don't let me forget to water the plants", now: now, calendar: calendar)
        == ReminderRequest(title: "water the plants", due: nil))
    #expect(ReminderParser.parse("remind me", now: now, calendar: calendar).title == nil)
}

/// Weekday phrases are resolved by NSDataDetector against the real clock, so this uses the real "now".
@Test func reminderOnADayWithoutATimeIsNineAM() throws {
    let realNow = Date()
    let request = ReminderParser.parse("remind me on friday to submit the report", now: realNow, calendar: calendar)
    #expect(request.title == "submit the report")
    let due = try #require(request.due)
    #expect(calendar.component(.weekday, from: due) == 6)
    #expect(calendar.component(.hour, from: due) == 9)
    #expect(due > realNow)
}

@Test(arguments: [
    ("set a timer for 10 minutes", TimerRequest(seconds: 600, name: nil)),
    ("set a pasta timer for 9 minutes", TimerRequest(seconds: 540, name: "pasta")),
    ("start a 25 minute pomodoro timer", TimerRequest(seconds: 1500, name: "pomodoro")),
    ("pomodoro", TimerRequest(seconds: 1500, name: "pomodoro")),
    ("timer for an hour and a half", TimerRequest(seconds: 5400, name: nil)),
    ("timer for half an hour", TimerRequest(seconds: 1800, name: nil)),
    ("set a timer for 1 hour 20 minutes", TimerRequest(seconds: 4800, name: nil)),
    ("timer for 90 seconds", TimerRequest(seconds: 90, name: nil)),
    ("tea timer for forty-five seconds", TimerRequest(seconds: 45, name: "tea")),
    ("set a ten minute timer", TimerRequest(seconds: 600, name: nil)),
    ("start a timer", TimerRequest(seconds: nil, name: nil)),
])
func timerRequests(_ transcript: String, _ expected: TimerRequest) {
    #expect(TimerParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("cancel the pasta timer", TimerTarget.named("pasta")),
    ("how long is left on the tea timer", .named("tea")),
    ("cancel the timer", .unspecified),
    ("how long is left on the timer", .unspecified),
    ("cancel all timers", .all),
    ("stop every timer", .all),
])
func timerTargets(_ transcript: String, _ expected: TimerTarget) {
    #expect(TimerParser.target(transcript) == expected)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=CaptureParserTests`
Expected: the build fails with `cannot find 'DictationParser' in scope`.

- [ ] **Step 3: Implement**

`Sources/Extraction/DictationParser.swift`:
```swift
import Foundation

/// The words to type: everything after "type" / "dictate" / "write", kept exactly as spoken.
public enum DictationParser {
    static let leadIns = ["type out", "write down", "type", "dictate", "write"] // longest first

    public static func text(from transcript: String) -> String? {
        var rest = Substring(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        var droppedCourtesy = true
        while droppedCourtesy {
            droppedCourtesy = false
            for phrase in LeadIn.courtesy {
                if let end = LeadIn.matchEnd(of: phrase, in: rest) {
                    rest = rest[end...]
                    droppedCourtesy = true
                }
            }
        }
        for phrase in leadIns {
            if let end = LeadIn.matchEnd(of: phrase, in: rest) {
                rest = rest[end...]
                break
            }
        }
        let text = rest.drop { $0 == " " || $0 == ":" || $0 == "," }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
```

`Sources/Extraction/NoteParser.swift`:
```swift
import Foundation

/// The text of a spoken note, after "note that", "take a note", and so on.
public enum NoteParser {
    static let leadIns = [
        "take a note that", "make a note that", "add a note saying", "add a note that", "save a note about",
        "take a note", "make a note", "add a note", "save a note", "note that", "note down", "jot down", "jot",
    ] // longest first

    public static func text(from transcript: String) -> String? {
        var rest = Substring(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        for phrase in leadIns {
            if let end = LeadIn.matchEnd(of: phrase, in: rest) {
                rest = rest[end...]
                break
            }
        }
        let text = rest.drop { $0 == " " || $0 == ":" || $0 == "," }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
```

`Sources/Extraction/ReminderParser.swift`:
```swift
import Foundation

public struct ReminderRequest: Equatable, Sendable {
    public var title: String?
    public var due: Date?

    public init(title: String?, due: Date?) {
        self.title = title
        self.due = due
    }
}

/// "remind me to call mum at 5pm" → title "call mum", due today 17:00.
public enum ReminderParser {
    static let leadIns = ["don t let me forget to", "set a reminder to", "add a reminder to", "remind me to", "remind me"]
    static let prepositions: Set<String> = ["at", "on", "in", "by", "to"]
    static let timeWords = ["morning", "afternoon", "evening", "tonight", "night", "noon", "midnight"]
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let dayWords = ["today", "tomorrow", "tonight", "monday", "tuesday", "wednesday", "thursday", "friday",
                           "saturday", "sunday", "next", "january", "february", "march", "april", "may", "june",
                           "july", "august", "september", "october", "november", "december"]

    public static func parse(_ transcript: String, now: Date, calendar: Calendar) -> ReminderRequest {
        var text = transcript
        var due: Date?

        // 1. "in 20 minutes", "in an hour", "in half an hour"
        let relative = /\bin\s+(?:half an|an?|\d+|[a-z]+(?:-[a-z]+)?)(?:\s+and\s+a\s+half)?\s+(?:minutes?|hours?)\b/.ignoresCase()
        if let match = text.firstMatch(of: relative),
           let seconds = TimerParser.parse(String(text[match.range])).seconds {
            due = now.addingTimeInterval(TimeInterval(seconds))
            text.removeSubrange(match.range)
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                  let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let detected = match.date,
                  let range = Range(match.range, in: text) {
            // 2. NSDataDetector resolves against the real clock; keep its day offset and time, apply to `now`.
            let phrase = text[range].lowercased()
            let hasTime = phrase.contains(/\d\s*(am|pm)\b/) || phrase.contains(/\d:\d{2}/) || phrase.contains(/\bat\s+\d/)
                || timeWords.contains(where: { phrase.contains($0) })
            let hasDay = dayWords.contains(where: { phrase.contains($0) }) || phrase.contains(/\d(st|nd|rd|th)\b/)
            // A time with no day ("at 5pm") is placed on `now`'s day; the detector may already have moved it
            // to tomorrow if the real clock is past that time, which would make tests depend on the hour.
            let dayOffset = hasDay ? calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                                             to: calendar.startOfDay(for: detected)).day ?? 0 : 0
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            let hour = hasTime ? calendar.component(.hour, from: detected) : 9
            let minute = hasTime ? calendar.component(.minute, from: detected) : 0
            var result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            if hasTime, !hasDay, result < now {
                result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
            // "on friday" said on a Friday after 9 AM means next Friday, not earlier today.
            if !hasTime, result < now, weekdays.contains(where: { phrase.contains($0) }) {
                result = calendar.date(byAdding: .day, value: 7, to: result) ?? result
            }
            due = result
            text.removeSubrange(range)
        }

        var title = LeadIn.strip(text.split(separator: " ").joined(separator: " "), phrases: leadIns)
        var words = title.split(separator: " ").map(String.init)
        while let first = words.first, prepositions.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, prepositions.contains(last.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?")))
        return ReminderRequest(title: title.isEmpty ? nil : title, due: due)
    }
}
```

`Sources/Extraction/TimerParser.swift`:
```swift
import Foundation

public struct TimerRequest: Equatable, Sendable {
    public var seconds: Int?
    public var name: String?

    public init(seconds: Int?, name: String?) {
        self.seconds = seconds
        self.name = name
    }
}

public enum TimerTarget: Equatable, Sendable {
    case all
    case named(String)
    case unspecified
}

/// "set a pasta timer for 9 minutes" → 540 seconds, named "pasta".
public enum TimerParser {
    static let units: [String: Int] = ["hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600,
                                       "minute": 60, "minutes": 60, "min": 60, "mins": 60,
                                       "second": 1, "seconds": 1, "sec": 1, "secs": 1]
    static let nameStopWords: Set<String> = ["a", "an", "the", "my", "set", "start", "new", "for", "me", "timer",
                                             "cancel", "stop", "delete", "clear", "remove", "on", "left", "is",
                                             "how", "long", "much", "time", "all", "every", "of", "and", "half"]

    public static func parse(_ transcript: String) -> TimerRequest {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        var seconds = 0
        var found = false
        for (i, word) in words.enumerated() {
            guard let unit = units[word] else { continue }
            if i >= 2, words[i - 2] == "half", words[i - 1] == "an" || words[i - 1] == "a" {
                seconds += unit / 2
                found = true
            } else if let amount = amount(before: i, in: words) {
                seconds += amount * unit
                found = true
            }
            if i + 3 < words.count, words[i + 1] == "and", words[i + 2] == "a", words[i + 3] == "half" {
                seconds += unit / 2
            }
        }
        if !found, words.contains("pomodoro") {
            seconds = 1500
            found = true
        }
        var name = nameBeforeTimer(words)
        if name == nil, words.contains("pomodoro") { name = "pomodoro" }
        return TimerRequest(seconds: found ? seconds : nil, name: name)
    }

    public static func target(_ transcript: String) -> TimerTarget {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        if words.contains("all") || words.contains("every") { return .all }
        if let name = nameBeforeTimer(words) { return .named(name) }
        return .unspecified
    }

    /// Digits, "a"/"an", or a spelled number (hyphenated first: "forty five" parses as 4005 when spaced).
    static func amount(before index: Int, in words: [String]) -> Int? {
        guard index >= 1 else { return nil }
        let previous = words[index - 1]
        if let value = Int(previous) { return value }
        if previous == "a" || previous == "an" { return 1 }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        if index >= 2, let value = formatter.number(from: "\(words[index - 2])-\(previous)")?.intValue { return value }
        return formatter.number(from: previous)?.intValue
    }

    /// The word(s) right before "timer" that aren't filler, numbers or units: "pasta timer" → "pasta".
    static func nameBeforeTimer(_ words: [String]) -> String? {
        guard let timerIndex = words.firstIndex(where: { $0 == "timer" || $0 == "timers" }) else { return nil }
        var nameWords: [String] = []
        var i = timerIndex - 1
        while i >= 0 {
            let word = words[i]
            let isNumber = Int(word) != nil || NumberFormatter.spellOutNumber(word) != nil
            if nameStopWords.contains(word) || units[word] != nil || isNumber { break }
            nameWords.insert(word, at: 0)
            i -= 1
        }
        return nameWords.isEmpty ? nil : nameWords.joined(separator: " ")
    }
}

extension NumberFormatter {
    /// The value of a spelled-out English number word ("ten"), or nil.
    static func spellOutNumber(_ word: String) -> Int? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter.number(from: word)?.intValue
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=CaptureParserTests`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Extraction Tests/ExtractionTests
git commit -m "Add parsers for dictation, notes, reminders and timers" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rules and intents for typing and capture

**Files:**
- Modify: `Sources/Routing/RoutingTypes.swift` (6 new `RoutedIntent` cases)
- Modify: `Sources/Routing/CommandRules.swift` (C rules at the top)
- Modify: `Sources/AssistantCore/Assistant.swift` (temporary case, replaced in Task 5)
- Modify: `Tests/RoutingTests/phrases.json` (12 phrases)
- Test: `Tests/RoutingTests/CaptureRulesTests.swift`

**Interfaces:**
- Consumes: `CommandRules.Rule` (existing).
- Produces: `RoutedIntent` cases `typeText`, `addNote`, `addReminder`, `startTimer`, `timerStatus`, `cancelTimer`.

- [ ] **Step 1: Write the failing tests**

`Tests/RoutingTests/CaptureRulesTests.swift`:
```swift
import Testing
@testable import Routing

@Test(arguments: [
    ("type see you soon", RoutedIntent.typeText),
    ("dictate thanks for the update", .typeText),
    ("write thank you so much", .typeText),
    ("take a note that the wifi password is on the fridge", .addNote),
    ("note down buy milk", .addNote),
    ("remind me to call mum at 5pm", .addReminder),
    ("don't let me forget to water the plants", .addReminder),
    ("set a timer for 10 minutes", .startTimer),
    ("25 minute pomodoro", .startTimer),
    ("how long is left on the timer", .timerStatus),
    ("how much time is left on the pasta timer", .timerStatus),
    ("cancel the pasta timer", .cancelTimer),
    ("stop the timer", .cancelTimer),
])
func captureCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("type i'll be there in ten minutes", RoutedIntent.typeText),
    ("write thank you so much", .typeText),
    ("note that the car needs servicing", .addNote),
    ("remind me at 8pm to take my medicine", .addReminder),
    ("remind me on friday to submit the report", .addReminder),
    ("timer for 3 minutes", .startTimer),
])
func heldOutCapturePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    ("type turn the volume down", RoutedIntent.typeText),
    ("remind me to lock the door", .addReminder),
    ("note that the tab is broken", .addNote),
    ("please remind me to close the window", .addReminder),
])
func captureWinsOverDeviceWords(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test func claudeRequestsStayWithLaya() {
    #expect(CommandRules.match("tell claude to write tests") == nil)
    #expect(CommandRules.match("open the reminders app") == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=CaptureRulesTests`
Expected: the build fails with `type 'RoutedIntent' has no member 'typeText'`.

- [ ] **Step 3: Add the intents**

In `Sources/Routing/RoutingTypes.swift`, add after `case revealFile = "reveal_file"`:
```swift
    case typeText = "type_text"
    case addNote = "add_note"
    case addReminder = "add_reminder"
    case startTimer = "start_timer"
    case timerStatus = "timer_status"
    case cancelTimer = "cancel_timer"
```
and add after `case .revealFile: "show a file in Finder"` in `displayName`:
```swift
        case .typeText: "type text"
        case .addNote: "save a note"
        case .addReminder: "add a reminder"
        case .startTimer: "start a timer"
        case .timerStatus: "check a timer"
        case .cancelTimer: "cancel a timer"
```

- [ ] **Step 4: Add the rules at the top**

In `Sources/Routing/CommandRules.swift`, insert as the **first** entries of `rules`, before the `screenshot` rule:
```swift
        // Typing and capture come first: dictated or noted text may contain any command words.
        Rule(intent: .typeText, anyOf: ["type", "dictate", "write"], startsWith: ["type", "dictate", "write"]),
        Rule(intent: .addNote, anyOf: ["take a note", "make a note", "note that", "note down", "jot", "add a note",
                                       "save a note"]),
        Rule(intent: .addReminder, anyOf: ["remind me", "reminder", "don t let me forget"]),
        Rule(intent: .cancelTimer, anyOf: ["timer", "timers"], alsoAnyOf: ["cancel", "stop", "delete", "clear", "remove"]),
        Rule(intent: .timerStatus, anyOf: ["timer", "timers"],
             alsoAnyOf: ["how long", "how much time", "left", "remaining", "status"]),
        Rule(intent: .startTimer, anyOf: ["timer", "countdown", "pomodoro"]),
```

- [ ] **Step 5: Temporary assistant case**

In `Sources/AssistantCore/Assistant.swift`, add as the last case of the `switch intent` in `perform(_:_:)`. Task 5 replaces it:
```swift
        case .typeText, .addNote, .addReminder, .startTimer, .timerStatus, .cancelTimer:
            return Outcome("Relay can't do that yet.", .info)
```

- [ ] **Step 6: Add routing phrases**

Append to `phrases` in `Tests/RoutingTests/phrases.json`, keeping `minimumAccuracy` at 1.0:
```json
    {"text": "type see you soon", "expected": "type_text"},
    {"text": "write thank you so much", "expected": "type_text"},
    {"text": "type turn the volume down", "expected": "type_text"},
    {"text": "note that the car needs servicing", "expected": "add_note"},
    {"text": "take a note buy milk", "expected": "add_note"},
    {"text": "remind me to call mum at 5pm", "expected": "add_reminder"},
    {"text": "remind me on friday to submit the report", "expected": "add_reminder"},
    {"text": "set a pasta timer for 9 minutes", "expected": "start_timer"},
    {"text": "25 minute pomodoro", "expected": "start_timer"},
    {"text": "how long is left on the timer", "expected": "timer_status"},
    {"text": "cancel the pasta timer", "expected": "cancel_timer"},
    {"text": "stop the timer", "expected": "cancel_timer"},
```

- [ ] **Step 7: Run all tests and the routing baseline**

Run: `make test`
Expected: everything passes, including all of A's and B's rule tests.

Run: `make test-routing`
Expected: `routing accuracy: 61/61 = 1.0`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Routing Sources/AssistantCore Tests/RoutingTests
git commit -m "Add rules for typing, notes, reminders and timers" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Capture types, timer store, note body and script, pasteboard swap

**Files:**
- Create: `Sources/SystemControls/CaptureControlling.swift`
- Create: `Sources/SystemControls/TimerStore.swift`
- Create: `Sources/SystemControls/NotificationScheduling.swift`
- Create: `Sources/SystemControls/NoteBody.swift`
- Create: `Sources/SystemControls/NoteScript.swift`
- Create: `Sources/SystemControls/PasteboardSwap.swift`
- Create: `Sources/SystemControls/DurationText.swift`
- Modify: `Sources/SystemControls/SystemControlling.swift` (`automationDenied(String)`, `remindersDenied`)
- Modify: `Sources/SystemControls/AppearanceScript.swift`, `Sources/SystemControls/FinderFolderScript.swift` (name the app)
- Modify: `Sources/AssistantCore/Assistant.swift` (error mapping, `.reminders` permission)
- Modify: `Sources/RelayApp/AppController.swift` (Reminders settings anchor)
- Modify: `Tests/AssistantCoreTests/SystemCommandTests.swift`, `Tests/AssistantCoreTests/Fakes.swift`, `Tests/SystemControlsTests/WorkspaceHelpersTests.swift` (new error shape)
- Test: `Tests/SystemControlsTests/CaptureHelpersTests.swift`

**Interfaces:**
- Consumes: `CommandResult`, `SystemControlError` (existing).
- Produces:
  - `public struct RelayTimer: Codable, Sendable, Equatable, Identifiable { id: UUID; name: String?; endsAt: Date; init(id:name:endsAt:) }`
  - `public struct TimerStart: Sendable, Equatable { timer: RelayTimer; notificationsAllowed: Bool; init(timer:notificationsAllowed:) }`
  - `public protocol CaptureControlling: Sendable` (spec §3)
  - `public struct TimerStore: Sendable { init(fileURL:); static var defaultFileURL; all(); active(now:); start(name:seconds:now:) throws -> RelayTimer; remove(id:) throws; prune(now:) throws }`
  - `public protocol NotificationScheduling: Sendable { schedule(id:title:body:after:) async throws; cancel(id:) async; allowed() async -> Bool }`
  - `public struct UserNotificationScheduler: NotificationScheduling`
  - `NoteBody.prepend(entry:at:to:) -> String`
  - `NoteScript.readArguments() -> [String]`, `NoteScript.writeArguments(body:) -> [String]`, `NoteScript.interpret(_:) throws -> String`
  - `@MainActor PasteboardSwap.snapshot(of:)`, `.write(_:to:) -> Int`, `.restore(_:to:ifChangeCount:) -> Bool`
  - `DurationText.describe(_ seconds: Int) -> String`
  - `SystemControlError.automationDenied(String)` and `.remindersDenied`
  - `PermissionKind.reminders`

- [ ] **Step 1: Write the failing tests**

`Tests/SystemControlsTests/CaptureHelpersTests.swift`:
```swift
import AppKit
import Foundation
import Testing
@testable import SystemControls

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)/timers.json")
}

private let start = Date(timeIntervalSince1970: 1_000_000)

@Test func timerStoreStartsListsAndRemoves() throws {
    let store = TimerStore(fileURL: temporaryFile())
    let pasta = try store.start(name: "pasta", seconds: 540, now: start)
    let tea = try store.start(name: "tea", seconds: 120, now: start)
    #expect(store.active(now: start).map(\.name) == ["tea", "pasta"]) // soonest first
    #expect(pasta.endsAt == start.addingTimeInterval(540))
    try store.remove(id: tea.id)
    #expect(store.active(now: start).map(\.id) == [pasta.id])
}

@Test func duplicateTimerNamesGetANumber() throws {
    let store = TimerStore(fileURL: temporaryFile())
    _ = try store.start(name: "pasta", seconds: 60, now: start)
    let second = try store.start(name: "pasta", seconds: 60, now: start)
    let third = try store.start(name: "pasta", seconds: 60, now: start)
    #expect(second.name == "pasta 2")
    #expect(third.name == "pasta 3")
}

@Test func endedTimersArePruned() throws {
    let store = TimerStore(fileURL: temporaryFile())
    _ = try store.start(name: nil, seconds: 10, now: start)
    let later = try store.start(name: "long", seconds: 1000, now: start)
    try store.prune(now: start.addingTimeInterval(60))
    #expect(store.all().map(\.id) == [later.id])
}

@Test func corruptOrMissingTimerFileMeansNoTimers() throws {
    let file = temporaryFile()
    #expect(TimerStore(fileURL: file).all().isEmpty)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not json".write(to: file, atomically: true, encoding: .utf8)
    let store = TimerStore(fileURL: file)
    #expect(store.all().isEmpty)
    _ = try store.start(name: "tea", seconds: 60, now: start)
    #expect(store.all().count == 1)
}

@Test func noteBodyAddsADatedLineUnderTheTitle() {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 28; components.hour = 17; components.minute = 5
    let date = Calendar.current.date(from: components)!
    #expect(NoteBody.prepend(entry: "car needs servicing", at: date, to: nil)
        == "<div><h1>Relay</h1></div><div>Sep 28, 17:05 — car needs servicing</div>")
    #expect(NoteBody.prepend(entry: "buy milk", at: date, to: "<div><h1>Relay</h1></div><div>Sep 27, 09:00 — old</div>")
        == "<div><h1>Relay</h1></div><div>Sep 28, 17:05 — buy milk</div><div>Sep 27, 09:00 — old</div>")
    #expect(NoteBody.prepend(entry: "say \"hi\" & <b>quit</b>", at: date, to: nil)
        .hasSuffix("say \"hi\" &amp; &lt;b&gt;quit&lt;/b&gt;</div>"))
}

@Test func noteScriptPassesTextOnlyAsAnArgument() throws {
    let body = "<div>tell application \"Finder\" to quit</div>"
    let arguments = NoteScript.writeArguments(body: body)
    #expect(arguments.last == body)
    #expect(!arguments.dropLast().contains(where: { $0.contains("Finder") }))
    #expect(NoteScript.readArguments().first == "-e")
}

@Test func noteScriptResultsAreInterpreted() throws {
    #expect(try NoteScript.interpret(CommandResult(status: 0, stdout: "<div>x</div>\n", stderr: "")) == "<div>x</div>")
    #expect(throws: SystemControlError.automationDenied("Notes")) {
        _ = try NoteScript.interpret(CommandResult(status: 1, stdout: "", stderr: "Not authorized (-1743)"))
    }
    #expect(throws: SystemControlError.failed("osascript exited 1")) {
        _ = try NoteScript.interpret(CommandResult(status: 1, stdout: "", stderr: ""))
    }
}

@MainActor @Test func pasteboardIsRestoredOnlyIfUntouched() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("relay-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("user's clipboard", forType: .string)

    let saved = PasteboardSwap.snapshot(of: pasteboard)
    let count = PasteboardSwap.write("dictated text", to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "dictated text")
    #expect(PasteboardSwap.restore(saved, to: pasteboard, ifChangeCount: count))
    #expect(pasteboard.string(forType: .string) == "user's clipboard")

    let again = PasteboardSwap.snapshot(of: pasteboard)
    let secondCount = PasteboardSwap.write("more text", to: pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("copied meanwhile", forType: .string) // the user copied something new
    #expect(!PasteboardSwap.restore(again, to: pasteboard, ifChangeCount: secondCount))
    #expect(pasteboard.string(forType: .string) == "copied meanwhile")
}

@Test(arguments: [(600, "10 minutes"), (60, "1 minute"), (5400, "1 hour 30 minutes"), (90, "1 minute 30 seconds"),
                  (45, "45 seconds"), (7200, "2 hours")])
func durationsReadNaturally(_ seconds: Int, _ expected: String) {
    #expect(DurationText.describe(seconds) == expected)
}
```

Update the error shape in existing tests:
- `Tests/AssistantCoreTests/SystemCommandTests.swift`: `(.automationDenied, .darkMode,` → `(.automationDenied("System Events"), .darkMode,`
- `Tests/SystemControlsTests/WorkspaceHelpersTests.swift`: `#expect(throws: SystemControlError.automationDenied)` → `#expect(throws: SystemControlError.automationDenied("Finder"))`
- `Tests/AssistantCoreTests/Fakes.swift`: `if finderDenied { throw SystemControlError.automationDenied }` → `if finderDenied { throw SystemControlError.automationDenied("Finder") }`

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=CaptureHelpersTests`
Expected: the build fails with `cannot find 'TimerStore' in scope` (and errors about `automationDenied` taking an argument).

- [ ] **Step 3: Change the error shape**

In `Sources/SystemControls/SystemControlling.swift`, replace `    case automationDenied` with:
```swift
    /// The user hasn't allowed Relay to control this app (AppleScript error -1743).
    case automationDenied(String)
    case remindersDenied
```
- In `Sources/SystemControls/AppearanceScript.swift`: `throw SystemControlError.automationDenied }` → `throw SystemControlError.automationDenied("System Events") }`
- In `Sources/SystemControls/FinderFolderScript.swift`: `throw SystemControlError.automationDenied }` → `throw SystemControlError.automationDenied("Finder") }`

In `Sources/AssistantCore/Assistant.swift`:
- add `case reminders` to `PermissionKind`
- in `control(_:_:)`, replace
  ```swift
              case .automationDenied:
                  missingPermission = .automation
                  return Outcome("Relay needs permission to control System Events for dark mode.", .problem)
  ```
  with
  ```swift
              case .automationDenied(let app):
                  missingPermission = .automation
                  if app == "Notes" {
                      return Outcome("Relay needs permission to control Notes to save notes.", .problem)
                  }
                  return Outcome("Relay needs permission to control System Events for dark mode.", .problem)
              case .remindersDenied:
                  missingPermission = .reminders
                  return Outcome("Relay needs Reminders access to add reminders.", .problem)
  ```
- in `creationFolder(for:)`, replace `} catch SystemControlError.automationDenied {` with `} catch SystemControlError.automationDenied(_) {`

In `Sources/RelayApp/AppController.swift`'s `openPrivacySettings(for:)`, add `case .reminders: "Privacy_Reminders"` after the `.automation` case.

- [ ] **Step 4: Implement the helpers**

`Sources/SystemControls/CaptureControlling.swift`:
```swift
import Foundation

public struct RelayTimer: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String?
    public let endsAt: Date

    public init(id: UUID, name: String?, endsAt: Date) {
        self.id = id
        self.name = name
        self.endsAt = endsAt
    }
}

public struct TimerStart: Sendable, Equatable {
    public let timer: RelayTimer
    public let notificationsAllowed: Bool

    public init(timer: RelayTimer, notificationsAllowed: Bool) {
        self.timer = timer
        self.notificationsAllowed = notificationsAllowed
    }
}

/// Typing, notes, reminders and timers. A protocol so the assistant can be tested with a fake.
public protocol CaptureControlling: Sendable {
    /// Pastes `text` into the app in front and returns that app's name.
    func typeText(_ text: String) async throws -> String
    func addNote(_ text: String) async throws
    func addReminder(title: String, due: Date?) async throws
    func startTimer(name: String?, seconds: Int) async throws -> TimerStart
    func activeTimers() async -> [RelayTimer]
    func cancelTimer(id: UUID) async
}
```

`Sources/SystemControls/TimerStore.swift`:
```swift
import Foundation

/// Running timers, saved as JSON so they survive Relay restarting. A missing or corrupt file means none.
public struct TimerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relay/timers.json")
    }

    public func all() -> [RelayTimer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RelayTimer].self, from: data)) ?? []
    }

    /// Timers that haven't ended, soonest first.
    public func active(now: Date) -> [RelayTimer] {
        all().filter { $0.endsAt > now }.sorted { $0.endsAt < $1.endsAt }
    }

    public func start(name: String?, seconds: Int, now: Date) throws -> RelayTimer {
        var timers = active(now: now)
        let timer = RelayTimer(id: UUID(), name: name.map { Self.uniqueName($0, among: timers) },
                               endsAt: now.addingTimeInterval(TimeInterval(seconds)))
        timers.append(timer)
        try save(timers)
        return timer
    }

    public func remove(id: UUID) throws {
        try save(all().filter { $0.id != id })
    }

    public func prune(now: Date) throws {
        try save(active(now: now))
    }

    /// "pasta" → "pasta 2" → "pasta 3" while earlier ones are still running.
    static func uniqueName(_ name: String, among timers: [RelayTimer]) -> String {
        let taken = Set(timers.compactMap(\.name))
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    private func save(_ timers: [RelayTimer]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(timers).write(to: fileURL, options: .atomic)
    }
}
```

`Sources/SystemControls/NotificationScheduling.swift`:
```swift
import Foundation
import UserNotifications

/// Schedules the notification that ends a timer. macOS delivers it even if Relay has quit.
public protocol NotificationScheduling: Sendable {
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws
    func cancel(id: String) async
    func allowed() async -> Bool
}

public struct UserNotificationScheduler: NotificationScheduling {
    public init() {}

    public func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    public func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
```

`Sources/SystemControls/NoteBody.swift`:
```swift
import Foundation

/// Builds the "Relay" note's HTML body with the newest dated line directly under the title.
public enum NoteBody {
    static let title = "<div><h1>Relay</h1></div>"

    public static func prepend(entry: String, at date: Date, to body: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm"
        let line = "<div>\(formatter.string(from: date)) — \(escape(entry))</div>"
        guard let body, !body.isEmpty else { return title + line }
        guard let heading = body.range(of: "</h1>") else { return title + line + body }
        var cut = heading.upperBound
        if body[cut...].hasPrefix("</div>") { cut = body.index(cut, offsetBy: 6) }
        return String(body[..<cut]) + line + String(body[cut...])
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
```

`Sources/SystemControls/NoteScript.swift`:
```swift
import Foundation

/// The two AppleScripts for the "Relay" note. Text only ever travels as an `osascript` argument.
public enum NoteScript {
    static let readLines = [
        "on run argv",
        "tell application \"Notes\"",
        "set found to notes whose name is \"Relay\"",
        "if (count of found) is 0 then return \"\"",
        "return body of item 1 of found",
        "end tell",
        "end run",
    ]
    static let writeLines = [
        "on run argv",
        "set newBody to item 1 of argv",
        "tell application \"Notes\"",
        "set found to notes whose name is \"Relay\"",
        "if (count of found) is 0 then",
        "make new note with properties {body:newBody}",
        "else",
        "set body of item 1 of found to newBody",
        "end if",
        "end tell",
        "end run",
    ]

    public static func readArguments() -> [String] {
        readLines.flatMap { ["-e", $0] }
    }

    public static func writeArguments(body: String) -> [String] {
        writeLines.flatMap { ["-e", $0] } + [body]
    }

    /// The note body on success; -1743 means Relay isn't allowed to control Notes.
    public static func interpret(_ result: CommandResult) throws -> String {
        guard result.status == 0 else {
            if result.stderr.contains("-1743") { throw SystemControlError.automationDenied("Notes") }
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "osascript exited \(result.status)" : reason)
        }
        return result.stdout.trimmingCharacters(in: .newlines)
    }
}
```

`Sources/SystemControls/PasteboardSwap.swift`:
```swift
import AppKit

/// Saves the clipboard, swaps in text to paste, then restores it only if nothing else changed it.
@MainActor
public enum PasteboardSwap {
    public typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    public static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    /// Writes `text` and returns the change count to compare against when restoring.
    public static func write(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    public static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard, ifChangeCount changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }
}
```

`Sources/SystemControls/DurationText.swift`:
```swift
/// "10 minutes", "1 hour 30 minutes", "1 minute 30 seconds". Seconds are left out once there are hours.
public enum DurationText {
    public static func describe(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if remainder > 0, hours == 0 { parts.append(remainder == 1 ? "1 second" : "\(remainder) seconds") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=CaptureHelpersTests`
Expected: all helper tests pass.

Run: `make test`
Expected: the whole suite passes (the renamed errors compile everywhere).

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Add timer store, note body and script, pasteboard swap; name the app in automation errors" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Real capture implementation

**Files:**
- Create: `Sources/SystemControls/MacCaptureControls.swift`
- Test: `Tests/SystemControlsTests/MacCaptureControlsTests.swift`

**Interfaces:**
- Consumes: Task 3's types and helpers; `KeyEvents.pressKey`, `Permissions`, `ProcessRunner`, `CommandRunning` (existing).
- Produces:
  - `public final class MacCaptureControls: CaptureControlling { init(runner:timers:scheduler:) }`
  - `MacCaptureControls.pruneTimers()`

- [ ] **Step 1: Write the failing tests**

`Tests/SystemControlsTests/MacCaptureControlsTests.swift`:
```swift
import Foundation
import Testing
@testable import SystemControls

actor FakeScheduler: NotificationScheduling {
    private(set) var scheduled: [(id: String, title: String, body: String, after: TimeInterval)] = []
    private(set) var cancelled: [String] = []
    var isAllowed = true
    var failSchedule = false

    func setAllowed(_ value: Bool) { isAllowed = value }
    func setFailSchedule(_ value: Bool) { failSchedule = value }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async throws {
        if failSchedule { throw SystemControlError.failed("not allowed") }
        scheduled.append((id, title, body, seconds))
    }
    func cancel(id: String) async { cancelled.append(id) }
    func allowed() async -> Bool { isAllowed }
}

private func store() -> TimerStore {
    TimerStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)/timers.json"))
}

@Test func startingATimerSchedulesItsNotification() async throws {
    let scheduler = FakeScheduler()
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "pasta", seconds: 540)
    #expect(start.timer.name == "pasta")
    #expect(start.notificationsAllowed)
    let scheduled = await scheduler.scheduled
    #expect(scheduled.count == 1)
    #expect(scheduled[0].id == start.timer.id.uuidString)
    #expect(scheduled[0].title == "Pasta timer done")
    #expect(scheduled[0].body == "9 minutes is up")
    #expect(scheduled[0].after == 540)
    #expect(await controls.activeTimers().map(\.id) == [start.timer.id])
}

@Test func unnamedTimerNotificationSaysTimerDone() async throws {
    let scheduler = FakeScheduler()
    _ = try await MacCaptureControls(timers: store(), scheduler: scheduler).startTimer(name: nil, seconds: 60)
    #expect(await scheduler.scheduled.first?.title == "Timer done")
}

@Test func timerIsKeptWhenNotificationsAreOff() async throws {
    let scheduler = FakeScheduler()
    await scheduler.setFailSchedule(true)
    await scheduler.setAllowed(false)
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "tea", seconds: 60)
    #expect(!start.notificationsAllowed)
    #expect(await controls.activeTimers().count == 1)
}

@Test func cancellingATimerRemovesItAndItsNotification() async throws {
    let scheduler = FakeScheduler()
    let controls = MacCaptureControls(timers: store(), scheduler: scheduler)
    let start = try await controls.startTimer(name: "tea", seconds: 60)
    await controls.cancelTimer(id: start.timer.id)
    #expect(await controls.activeTimers().isEmpty)
    #expect(await scheduler.cancelled == [start.timer.id.uuidString])
}

@Test func addingANoteReadsThenWritesTheRelayNote() async throws {
    let runner = FakeRunner(installed: [])
    await runner.setRunResult(CommandResult(status: 0, stdout: "<div><h1>Relay</h1></div><div>Sep 27, 09:00 — old</div>\n", stderr: ""))
    try await MacCaptureControls(runner: runner, timers: store(), scheduler: FakeScheduler()).addNote("buy milk")
    let calls = await runner.calls
    #expect(calls.count == 2)
    #expect(calls.allSatisfy { $0.first == "/usr/bin/osascript" })
    let written = try #require(calls.last?.last)
    #expect(written.hasPrefix("<div><h1>Relay</h1></div><div>"))
    #expect(written.contains("— buy milk</div><div>Sep 27, 09:00 — old</div>"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=MacCaptureControlsTests`
Expected: the build fails with `cannot find 'MacCaptureControls' in scope`.

- [ ] **Step 3: Implement**

`Sources/SystemControls/MacCaptureControls.swift`:
```swift
import AppKit
import EventKit
import Foundation

/// The real implementation: clipboard + ⌘V, Notes via osascript, EventKit reminders, scheduled timers.
public final class MacCaptureControls: CaptureControlling {
    private let runner: any CommandRunning
    private let timers: TimerStore
    private let scheduler: any NotificationScheduling

    public init(runner: any CommandRunning = ProcessRunner(),
                timers: TimerStore = TimerStore(fileURL: TimerStore.defaultFileURL),
                scheduler: any NotificationScheduling = UserNotificationScheduler()) {
        self.runner = runner
        self.timers = timers
        self.scheduler = scheduler
    }

    // MARK: Typing

    public func typeText(_ text: String) async throws -> String {
        try Permissions.requireAccessibility()
        let (app, snapshot, changeCount) = try await MainActor.run { () throws -> (String, PasteboardSwap.Snapshot, Int) in
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != Bundle.main.bundleIdentifier else { throw SystemControlError.noFrontWindow }
            if NSApp.keyWindow != nil { _ = front.activate() } // don't paste into Relay's own panel
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSwap.snapshot(of: pasteboard)
            let changeCount = PasteboardSwap.write(text, to: pasteboard)
            KeyEvents.pressKey(9 /* kVK_ANSI_V */, flags: .maskCommand)
            return (front.localizedName ?? "the front app", snapshot, changeCount)
        }
        try? await Task.sleep(for: .milliseconds(300)) // let the app read the clipboard first
        await MainActor.run { _ = PasteboardSwap.restore(snapshot, to: .general, ifChangeCount: changeCount) }
        return app
    }

    // MARK: Notes

    public func addNote(_ text: String) async throws {
        let body = try NoteScript.interpret(try await runner.run("/usr/bin/osascript", NoteScript.readArguments()))
        let updated = NoteBody.prepend(entry: text, at: Date(), to: body)
        _ = try NoteScript.interpret(try await runner.run("/usr/bin/osascript", NoteScript.writeArguments(body: updated)))
    }

    // MARK: Reminders

    public func addReminder(title: String, due: Date?) async throws {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { throw SystemControlError.remindersDenied }
        guard let list = store.defaultCalendarForNewReminders() else {
            throw SystemControlError.failed("no default Reminders list")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw SystemControlError.failed(error.localizedDescription)
        }
    }

    // MARK: Timers

    public func startTimer(name: String?, seconds: Int) async throws -> TimerStart {
        let timer = try timers.start(name: name, seconds: seconds, now: Date())
        let title = timer.name.map { $0.prefix(1).uppercased() + $0.dropFirst() + " timer done" } ?? "Timer done"
        do {
            try await scheduler.schedule(id: timer.id.uuidString, title: title,
                                         body: "\(DurationText.describe(seconds)) is up", after: TimeInterval(seconds))
        } catch {
            // The timer is still saved; the assistant tells the user notifications are off.
        }
        return TimerStart(timer: timer, notificationsAllowed: await scheduler.allowed())
    }

    public func activeTimers() async -> [RelayTimer] {
        timers.active(now: Date())
    }

    public func cancelTimer(id: UUID) async {
        try? timers.remove(id: id)
        await scheduler.cancel(id: id.uuidString)
    }

    /// Removes ended timers; called at launch.
    public func pruneTimers() {
        try? timers.prune(now: Date())
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=MacCaptureControlsTests`
Expected: 5 tests pass. If Swift 6 complains about `EKEventStore` crossing an `await`, keep it a local constant (it's never shared) and, if needed, mark the local `nonisolated(unsafe) let store = EKEventStore()`. Record a ruling if you do.

Run: `make test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemControls Tests/SystemControlsTests
git commit -m "Add real capture controls: paste typing, Notes, Reminders and scheduled timers" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Assistant handles typing, notes, reminders and timers

**Files:**
- Create: `Sources/AssistantCore/CaptureFormat.swift`
- Modify: `Sources/AssistantCore/Assistant.swift`
- Modify: `Sources/RelayApp/AppController.swift` (pass `MacCaptureControls`, prune at launch)
- Modify: `Tests/AssistantCoreTests/Fakes.swift` (`FakeCapture`; `Harness`)
- Test: `Tests/AssistantCoreTests/CaptureCommandTests.swift`

**Interfaces:**
- Consumes: Task 1 parsers; Task 2 intents; Task 3/4 `CaptureControlling`, `RelayTimer`, `TimerStart`, `DurationText`, `MacCaptureControls`, the new errors and permission kind.
- Produces:
  - `AssistantDependencies.capture`, as the init parameter `capture:` after `workspace:`
  - `Assistant.timers: [RelayTimer]`
  - `Assistant.refreshTimers() async`
  - `Assistant.cancelTimer(_:) async`
  - `CaptureFormat.duration(_:)`, `.remaining(_:now:)`, `.displayName(_:)`, `.reminderTime(_:now:calendar:)`

- [ ] **Step 1: Write the fake and the failing tests**

In `Tests/AssistantCoreTests/Fakes.swift`:
- add `let capture = FakeCapture()` to `Harness` after `let workspace = FakeWorkspace()`
- in `Harness.init`, pass `capture: capture` directly after `workspace: workspace,`
- add this fake:
```swift
actor FakeCapture: CaptureControlling {
    private(set) var calls: [String] = []
    var frontApp = "TextEdit"
    var failure: SystemControlError?
    var notificationsAllowed = true
    var running: [RelayTimer] = []

    func fail(with error: SystemControlError?) { failure = error }
    func setNotificationsAllowed(_ value: Bool) { notificationsAllowed = value }
    func setRunning(_ timers: [RelayTimer]) { running = timers }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func typeText(_ text: String) throws -> String { try record("type(\(text))"); return frontApp }
    func addNote(_ text: String) throws { try record("note(\(text))") }
    func addReminder(title: String, due: Date?) throws { try record("reminder(\(title), due: \(due != nil))") }
    func startTimer(name: String?, seconds: Int) throws -> TimerStart {
        try record("start(\(name ?? "-"), \(seconds))")
        let timer = RelayTimer(id: UUID(), name: name, endsAt: Date().addingTimeInterval(TimeInterval(seconds)))
        running.append(timer)
        return TimerStart(timer: timer, notificationsAllowed: notificationsAllowed)
    }
    func activeTimers() -> [RelayTimer] { running }
    func cancelTimer(id: UUID) {
        calls.append("cancel(\(running.first { $0.id == id }?.name ?? "-"))")
        running.removeAll { $0.id == id }
    }
}
```

`Tests/AssistantCoreTests/CaptureCommandTests.swift`:
```swift
import Foundation
import Testing
@testable import AssistantCore
@testable import Routing
@testable import SystemControls

private func timer(_ name: String?, in seconds: TimeInterval) -> RelayTimer {
    RelayTimer(id: UUID(), name: name, endsAt: Date().addingTimeInterval(seconds))
}

// MARK: Typing

@MainActor @Test func typesTheDictatedText() async {
    let h = Harness(transcript: "type see you soon.", outcome: .intent(.typeText))
    await h.speak()
    #expect(await h.capture.calls == ["type(see you soon.)"])
    #expect(h.assistant.message == "Typed into TextEdit")
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func typingProblems() async {
    let e = Harness(transcript: "type", outcome: .intent(.typeText))
    await e.speak()
    #expect(e.assistant.message == "What should I type?")

    let n = Harness(transcript: "type hello", outcome: .intent(.typeText))
    await n.capture.fail(with: .noFrontWindow)
    await n.speak()
    #expect(n.assistant.message == "There's no app window in front to type into.")
}

// MARK: Notes

@MainActor @Test func savesANote() async {
    let h = Harness(transcript: "note that the car needs servicing", outcome: .intent(.addNote))
    await h.speak()
    #expect(await h.capture.calls == ["note(the car needs servicing)"])
    #expect(h.assistant.message == "Noted: the car needs servicing")
}

@MainActor @Test func longNotesAreShortenedInThePill() async {
    let text = String(repeating: "a", count: 50)
    let h = Harness(transcript: "note that \(text)", outcome: .intent(.addNote))
    await h.speak()
    #expect(h.assistant.message == "Noted: \(String(repeating: "a", count: 40))…")
}

@MainActor @Test func noteProblems() async {
    let e = Harness(transcript: "take a note", outcome: .intent(.addNote))
    await e.speak()
    #expect(e.assistant.message == "What should the note say?")

    let d = Harness(transcript: "note that x", outcome: .intent(.addNote))
    await d.capture.fail(with: .automationDenied("Notes"))
    await d.speak()
    #expect(d.assistant.message == "Relay needs permission to control Notes to save notes.")
    #expect(d.assistant.missingPermission == .automation)

    let f = Harness(transcript: "note that x", outcome: .intent(.addNote))
    await f.capture.fail(with: .failed("timed out"))
    await f.speak()
    #expect(f.assistant.message == "Couldn't save the note: timed out")
}

// MARK: Reminders

@MainActor @Test func remindersWithAndWithoutATime() async {
    let plain = Harness(transcript: "remind me to buy milk", outcome: .intent(.addReminder))
    await plain.speak()
    #expect(await plain.capture.calls == ["reminder(buy milk, due: false)"])
    #expect(plain.assistant.message == "Reminder added: buy milk")

    let timed = Harness(transcript: "remind me tomorrow at 9 to pay rent", outcome: .intent(.addReminder))
    await timed.speak()
    #expect(await timed.capture.calls == ["reminder(pay rent, due: true)"])
    #expect(timed.assistant.message == "Reminder set: pay rent — tomorrow 9:00 AM")
}

@MainActor @Test func reminderProblems() async {
    let e = Harness(transcript: "remind me", outcome: .intent(.addReminder))
    await e.speak()
    #expect(e.assistant.message == "What should I remind you about?")

    let d = Harness(transcript: "remind me to call", outcome: .intent(.addReminder))
    await d.capture.fail(with: .remindersDenied)
    await d.speak()
    #expect(d.assistant.message == "Relay needs Reminders access to add reminders.")
    #expect(d.assistant.missingPermission == .reminders)

    let f = Harness(transcript: "remind me to call", outcome: .intent(.addReminder))
    await f.capture.fail(with: .failed("no default Reminders list"))
    await f.speak()
    #expect(f.assistant.message == "Couldn't add the reminder: no default Reminders list")
}

// MARK: Timers

@MainActor @Test func startsNamedAndUnnamedTimers() async {
    let p = Harness(transcript: "set a pasta timer for 9 minutes", outcome: .intent(.startTimer))
    await p.speak()
    #expect(await p.capture.calls == ["start(pasta, 540)"])
    #expect(p.assistant.message == "Pasta timer set for 9 minutes")
    #expect(p.assistant.timers.count == 1)

    let u = Harness(transcript: "set a timer for 10 minutes", outcome: .intent(.startTimer))
    await u.speak()
    #expect(u.assistant.message == "Timer set for 10 minutes")
}

@MainActor @Test func timerWithNotificationsOffSaysSo() async {
    let h = Harness(transcript: "set a timer for 10 minutes", outcome: .intent(.startTimer))
    await h.capture.setNotificationsAllowed(false)
    await h.speak()
    #expect(h.assistant.message
        == "Timer set for 10 minutes, but notifications are off for Relay, so turn them on to hear it")
}

@MainActor @Test func timerWithoutADurationAsks() async {
    let h = Harness(transcript: "start a timer", outcome: .intent(.startTimer))
    await h.speak()
    #expect(h.assistant.message == "How long? Try “10 minutes”.")
}

@MainActor @Test func timeLeft() async {
    let none = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await none.speak()
    #expect(none.assistant.message == "No timers running")

    let one = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await one.capture.setRunning([timer(nil, in: 7200.5)])
    await one.speak()
    #expect(one.assistant.message == "2 hours left")

    let many = Harness(transcript: "how long is left on the timer", outcome: .intent(.timerStatus))
    await many.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await many.speak()
    #expect(many.assistant.message == "Pasta: 3 min left · Tea: <1 min left")

    let named = Harness(transcript: "how long is left on the soup timer", outcome: .intent(.timerStatus))
    await named.capture.setRunning([timer("pasta", in: 150)])
    await named.speak()
    #expect(named.assistant.message == "No soup timer running")
}

@MainActor @Test func cancellingTimers() async {
    let named = Harness(transcript: "cancel the pasta timer", outcome: .intent(.cancelTimer))
    await named.capture.setRunning([timer("pasta", in: 150), timer("pasta 2", in: 300), timer("tea", in: 30)])
    await named.speak()
    #expect(await named.capture.calls == ["cancel(pasta)"])
    #expect(named.assistant.message == "Cancelled the pasta timer")
    #expect(named.assistant.timers.count == 2)

    let which = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await which.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await which.speak()
    #expect(which.assistant.message == "Which timer? Pasta, Tea")

    let only = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await only.capture.setRunning([timer(nil, in: 30)])
    await only.speak()
    #expect(only.assistant.message == "Cancelled the timer")

    let all = Harness(transcript: "cancel all timers", outcome: .intent(.cancelTimer))
    await all.capture.setRunning([timer("pasta", in: 150), timer("tea", in: 30)])
    await all.speak()
    #expect(all.assistant.message == "Cancelled 2 timers")

    let unknown = Harness(transcript: "cancel the soup timer", outcome: .intent(.cancelTimer))
    await unknown.capture.setRunning([timer("pasta", in: 150)])
    await unknown.speak()
    #expect(unknown.assistant.message == "No soup timer running")

    let none = Harness(transcript: "cancel the timer", outcome: .intent(.cancelTimer))
    await none.speak()
    #expect(none.assistant.message == "No timers running")
}

@MainActor @Test func panelCancelAndRefresh() async {
    let h = Harness()
    let tea = timer("tea", in: 60)
    await h.capture.setRunning([tea])
    await h.assistant.refreshTimers()
    #expect(h.assistant.timers == [tea])
    await h.assistant.cancelTimer(tea)
    #expect(h.assistant.timers.isEmpty)
}

// MARK: Formatting

@Test func remainingTimeFormats() {
    let now = Date()
    #expect(CaptureFormat.remaining([], now: now) == "No timers running")
    #expect(CaptureFormat.remaining([RelayTimer(id: UUID(), name: nil, endsAt: now.addingTimeInterval(432))], now: now)
        == "7 minutes 12 seconds left")
    #expect(CaptureFormat.displayName(RelayTimer(id: UUID(), name: "pasta 2", endsAt: now)) == "Pasta 2")
}

@Test func reminderTimesReadNaturally() {
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 28; components.hour = 16
    let now = calendar.date(from: components)! // a Monday
    func at(_ days: Int, _ hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: days, to: now)!)!
    }
    #expect(CaptureFormat.reminderTime(at(0, 17), now: now, calendar: calendar) == "today 5:00 PM")
    #expect(CaptureFormat.reminderTime(at(1, 9), now: now, calendar: calendar) == "tomorrow 9:00 AM")
    #expect(CaptureFormat.reminderTime(at(4, 9), now: now, calendar: calendar) == "Fri 9:00 AM")
    #expect(CaptureFormat.reminderTime(at(10, 9), now: now, calendar: calendar) == "Oct 8 9:00 AM")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=AssistantCoreTests`
Expected: the build fails with `extra argument 'capture' in call` / `cannot find 'CaptureFormat' in scope`.

- [ ] **Step 3: Implement formatting**

`Sources/AssistantCore/CaptureFormat.swift`:
```swift
import Foundation
import SystemControls

/// Wording for timers and reminders in the pill and panel.
public enum CaptureFormat {
    public static func duration(_ seconds: Int) -> String {
        DurationText.describe(seconds)
    }

    /// "Pasta 2", or "Timer" for an unnamed timer.
    public static func displayName(_ timer: RelayTimer) -> String {
        guard let name = timer.name else { return "Timer" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// One timer: "7 minutes 12 seconds left". Several: "Pasta: 3 min left · Tea: <1 min left".
    public static func remaining(_ timers: [RelayTimer], now: Date) -> String {
        guard !timers.isEmpty else { return "No timers running" }
        func secondsLeft(_ timer: RelayTimer) -> Int { max(0, Int(timer.endsAt.timeIntervalSince(now).rounded(.up))) }
        if timers.count == 1 { return "\(duration(secondsLeft(timers[0]))) left" }
        return timers.map { timer in
            let seconds = secondsLeft(timer)
            let minutes = seconds < 60 ? "<1 min" : "\(Int((Double(seconds) / 60).rounded(.up))) min"
            return "\(displayName(timer)): \(minutes) left"
        }.joined(separator: " · ")
    }

    /// "today 5:00 PM", "tomorrow 9:00 AM", "Fri 9:00 AM" within the week, otherwise "Oct 3 9:00 AM".
    public static func reminderTime(_ due: Date, now: Date, calendar: Calendar) -> String {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: due)
        }
        let time = format("h:mm a")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "today \(time)"
        case 1: return "tomorrow \(time)"
        case 2...6: return "\(format("EEE")) \(time)"
        default: return "\(format("MMM d")) \(time)"
        }
    }
}
```

- [ ] **Step 4: Implement in the assistant**

In `Sources/AssistantCore/Assistant.swift`:

1. In `AssistantDependencies`, add `public var capture: any CaptureControlling` after `workspace`. Add the init parameter `capture: any CaptureControlling` right after `workspace: any WorkspaceControlling,`, and assign it.
2. Add state next to `fileMatches`:
```swift
    /// Running timers, for the panel's Timers section.
    public private(set) var timers: [RelayTimer] = []
```
3. Replace the temporary `case .typeText, .addNote, … return Outcome("Relay can't do that yet.", .info)` from Task 2 with:
```swift
        case .typeText:
            guard let dictated = DictationParser.text(from: text) else { return Outcome("What should I type?", .info) }
            return await control("type into") {
                let app = try await self.deps.capture.typeText(dictated)
                return Outcome("Typed into \(app)", .success, extracted: dictated)
            }

        case .addNote:
            guard let note = NoteParser.text(from: text) else { return Outcome("What should the note say?", .info) }
            return await control("save the note") {
                try await self.deps.capture.addNote(note)
                let preview = note.count > 40 ? String(note.prefix(40)) + "…" : note
                return Outcome("Noted: \(preview)", .success, extracted: note)
            }

        case .addReminder:
            let calendar = Calendar.current
            let now = Date()
            let request = ReminderParser.parse(text, now: now, calendar: calendar)
            guard let title = request.title else { return Outcome("What should I remind you about?", .info) }
            return await control("add the reminder") {
                try await self.deps.capture.addReminder(title: title, due: request.due)
                guard let due = request.due else { return Outcome("Reminder added: \(title)", .success, extracted: title) }
                return Outcome("Reminder set: \(title) — \(CaptureFormat.reminderTime(due, now: now, calendar: calendar))",
                               .success, extracted: title)
            }

        case .startTimer:
            let request = TimerParser.parse(text)
            guard let seconds = request.seconds, seconds > 0 else { return Outcome("How long? Try “10 minutes”.", .info) }
            return await control("start the timer") {
                let start = try await self.deps.capture.startTimer(name: request.name, seconds: seconds)
                self.timers = await self.deps.capture.activeTimers()
                let label = start.timer.name == nil ? "Timer" : "\(CaptureFormat.displayName(start.timer)) timer"
                var message = "\(label) set for \(CaptureFormat.duration(seconds))"
                if !start.notificationsAllowed {
                    message += ", but notifications are off for Relay, so turn them on to hear it"
                }
                return Outcome(message, .success)
            }

        case .timerStatus:
            let running = await deps.capture.activeTimers()
            timers = running
            guard !running.isEmpty else { return Outcome("No timers running", .info) }
            if case .named(let name) = TimerParser.target(text) {
                let matching = running.filter { $0.name?.hasPrefix(name) == true }
                guard !matching.isEmpty else { return Outcome("No \(name) timer running", .info) }
                return Outcome(CaptureFormat.remaining(matching, now: Date()), .success)
            }
            return Outcome(CaptureFormat.remaining(running, now: Date()), .success)

        case .cancelTimer:
            let running = await deps.capture.activeTimers()
            guard !running.isEmpty else {
                timers = []
                return Outcome("No timers running", .info)
            }
            let chosen: [RelayTimer]
            switch TimerParser.target(text) {
            case .all:
                chosen = running
            case .named(let name):
                chosen = Array(running.filter { $0.name == name }.prefix(1))
                guard !chosen.isEmpty else { return Outcome("No \(name) timer running", .info) }
            case .unspecified:
                guard running.count == 1 else {
                    return Outcome("Which timer? \(running.map(CaptureFormat.displayName).joined(separator: ", "))", .info)
                }
                chosen = running
            }
            for timer in chosen { await deps.capture.cancelTimer(id: timer.id) }
            timers = await deps.capture.activeTimers()
            if chosen.count > 1 { return Outcome("Cancelled \(chosen.count) timers", .success) }
            return Outcome(chosen[0].name.map { "Cancelled the \($0) timer" } ?? "Cancelled the timer", .success)
```
4. Add these public methods next to `pick(_:)`:
```swift
    public func refreshTimers() async {
        timers = await deps.capture.activeTimers()
    }

    /// Cancels a timer from the panel's ✕.
    public func cancelTimer(_ timer: RelayTimer) async {
        await deps.capture.cancelTimer(id: timer.id)
        timers = await deps.capture.activeTimers()
    }
```

In `Sources/RelayApp/AppController.swift`:
- add a stored property `private let capture: MacCaptureControls` (no default value)
- at the start of `init()`, after `Preferences.registerDefaults()`, add `let capture = MacCaptureControls()` and `self.capture = capture`. A class can't read its own stored property before all properties are set, so the dependencies below use the local.
- in the `AssistantDependencies(...)` call, pass `capture: capture,` directly after `workspace: MacWorkspaceControls(),`
- in `start()`, after `Notifier.requestAuthorization()`, add `capture.pruneTimers()`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=AssistantCoreTests`
Expected: all AssistantCore tests pass.

Run: `make test`
Expected: the whole suite passes.

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests/AssistantCoreTests
git commit -m "Handle typing, notes, reminders and timers in the assistant" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Timers in the panel, permissions text, checklist

**Files:**
- Modify: `Sources/RelayApp/PanelView.swift` (Timers section)
- Modify: `Resources/Info.plist` (Reminders usage text)
- Modify: `docs/manual-checklist.md`
- Modify: `docs/superpowers/specs/2026-09-28-relay-typing-capture-design.md` (record the NSDataDetector findings, see Step 4)

**Interfaces:**
- Consumes: `Assistant.timers`, `refreshTimers()`, `cancelTimer(_:)`, `CaptureFormat.displayName` (Task 5); `RelayTimer` (Task 3).
- Produces: UI only.

This task is UI glue, verified by the build and the manual checklist.

- [ ] **Step 1: The Timers section**

In `Sources/RelayApp/PanelView.swift`, directly after the `if !assistant.fileMatches.isEmpty { … }` block, add:
```swift
            if !assistant.timers.isEmpty {
                TimersView(timers: assistant.timers) { timer in
                    Task { await assistant.cancelTimer(timer) }
                }
            }
```
On the panel's outer `VStack`, add `.task { await assistant.refreshTimers() }` next to its existing modifiers, and at the end of the file add:
```swift
/// Running timers with a live countdown and a ✕ to cancel each.
struct TimersView: View {
    let timers: [RelayTimer]
    let cancel: (RelayTimer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timers").font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(timers.filter { $0.endsAt > context.date }) { timer in
                        HStack {
                            Text(CaptureFormat.displayName(timer))
                            Spacer()
                            Text(Self.clock(timer.endsAt.timeIntervalSince(context.date))).monospacedDigit()
                            Button { cancel(timer) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// "8:59", or "1:05:00" for timers over an hour.
    static func clock(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 2: Reminders permission text**

In `Resources/Info.plist`, add inside the `<dict>`:
```xml
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Relay adds reminders you ask for to Apple Reminders.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Relay adds reminders you ask for to Apple Reminders.</string>
```

- [ ] **Step 3: Manual checklist**

In `docs/manual-checklist.md`, add before the `decisions.jsonl` line:
```markdown
- [ ] Copy some text, then with TextEdit in front say "type see you soon.": "see you soon." appears; paste again afterwards and your original copied text comes back
- [ ] "Type" into a browser text field (e.g. a search box) works the same
- [ ] "Note that the car needs servicing": Relay asks to control Notes once; a note called "Relay" gets a dated line at the top; a second note goes above the first
- [ ] "Remind me to buy milk": Relay asks for Reminders once; the reminder appears in your default list with no alert
- [ ] "Remind me in 2 minutes to stretch": the reminder alerts about 2 minutes later
- [ ] "Set a pasta timer for 1 minute": the panel shows it counting down; a notification with sound arrives when it ends
- [ ] Start a 2-minute timer, quit Relay, wait: the notification still arrives
- [ ] Start two timers; "how long is left on the timer" lists both; "cancel the pasta timer" removes only that one; the panel's ✕ cancels the other
```

- [ ] **Step 4: Record the date-detection findings in the spec**

In `docs/superpowers/specs/2026-09-28-relay-typing-capture-design.md` §2.3, after the due-date list, add:
```markdown
Implementation notes (measured 2026-09-28): `NSDataDetector` gives day-only phrases a default of 12:00
noon, so the parser decides whether a time was spoken from the matched text: digits with am/pm, "h:mm",
"at <digit>", or morning/afternoon/evening/tonight/night/noon/midnight. It also resolves dates against the
real clock only, so the parser keeps the detector's day offset and time and applies them to the given `now`.
Weekday tests ("on friday") therefore use the real current date.
```

- [ ] **Step 5: Build, test and bundle**

Run: `make test`
Expected: the whole suite passes.

Run: `make test-routing`
Expected: `routing accuracy: 61/61 = 1.0`.

Run: `make app`
Expected: it ends with `Built build/Relay.app`.

Run: `plutil -p build/Relay.app/Contents/Info.plist | grep NSReminders`
Expected: both Reminders keys are printed.

- [ ] **Step 6: Commit**

```bash
git add Sources/RelayApp Resources/Info.plist docs/manual-checklist.md docs/superpowers/specs/2026-09-28-relay-typing-capture-design.md
git commit -m "Show running timers in the panel, add Reminders permission text and checklist" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
