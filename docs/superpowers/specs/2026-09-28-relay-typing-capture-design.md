# Relay sub-project C: typing and quick capture (design)

Date: 2026-09-28
Status: approved in conversation, awaiting written-spec review
Builds on: sub-projects A and B (merged to `master`)

## 1. Purpose

Relay types dictated text into the app in front, saves quick notes to Apple Notes, adds Apple Reminders,
and runs named timers. It keeps the earlier constraints: no new dependencies or models, small and quick,
hotkey start and stop, and non-destructive only.

**Success:** each of these works first time and shows its result in the pill:
- "type see you in five minutes.", "write thank you so much"
- "note that the car needs servicing"
- "remind me to call mum at 5pm", "remind me on Friday to submit the report", "remind me to buy milk"
- "set a pasta timer for 9 minutes", "25 minute pomodoro", "how long is left on the timer", "cancel the
  pasta timer"

**User decisions made in brainstorming:**
- **Typing:** paste through the clipboard, then restore the previous clipboard.
- **Notes:** one running Apple Note called "Relay", with each note added as a dated line at the top.
- **Reminders:** without a spoken time, add a plain reminder with no due date. With a time, set a due date
  and an alert.
- **Timers:** start, several named timers, time left, and cancel.
- **Timer storage:** scheduled macOS notifications plus a small `timers.json`, so timers still fire if Relay
  quits.
- **"write"** stays a typing trigger, knowing that "write a test for the parser" with no mention of Claude
  types that sentence.

## 2. Routing

### 2.1 New intents

New `RoutedIntent` cases, with their raw values: `typeText` ("type_text"), `addNote` ("add_note"),
`addReminder` ("add_reminder"), `startTimer` ("start_timer"), `timerStatus` ("timer_status"), `cancelTimer`
("cancel_timer"). Each gets a `displayName`.

### 2.2 Rules

C's rules go at the **top** of `CommandRules.rules`, before A's `screenshot` rule. Dictated or noted text
can contain any command words ("type turn the volume down"). The global guards run first as before: a
Claude mention, web lead-ins, the open/launch guard, and dropping polite openers.

| # | Intent | anyOf | alsoAnyOf | startsWith |
|---|---|---|---|---|
| C1 | `typeText` | type, dictate, write | | type, dictate, write |
| C2 | `addNote` | take a note, make a note, note that, note down, jot, add a note, save a note | | |
| C3 | `addReminder` | remind me, reminder, don t let me forget | | |
| C4 | `cancelTimer` | timer, timers | cancel, stop, delete, clear, remove | |
| C5 | `timerStatus` | timer, timers | how long, how much time, left, remaining, status | |
| C6 | `startTimer` | timer, countdown, pomodoro | | |

**Priority cases (tested):**
- "type turn the volume down" → `typeText`
- "remind me to lock the door" → `addReminder`
- "note that the tab is broken" → `addNote`
- "stop the timer" → `cancelTimer`, not media play/pause
- "tell claude to write tests" → Laya (Claude guard)

### 2.3 Detail parsers (in `Extraction`, pure)

**`DictationParser.text(from:) -> String?`**
- Removes a leading "type out", "type", "dictate", "write down" or "write" (longest first), plus following
  spaces, ":" or ",".
- **Keeps the rest verbatim**, including casing and ending punctuation: "type see you soon." → "see you
  soon.".
- Returns nil if nothing is left.

**`NoteParser.text(from:) -> String?`**
- Removes a leading note phrase: "take a note that", "take a note", "make a note that", "make a note",
  "note that", "note down", "jot down", "jot", "add a note saying", "add a note that", "add a note", "save a
  note about", "save a note".
- Keeps the rest verbatim, and returns nil if nothing is left.

**`ReminderParser.parse(_:now:calendar:) -> ReminderRequest`**, where
`ReminderRequest { title: String?; due: Date? }`.

The due date:
1. **Relative first:** "in N minutes/hours" or "in an hour" / "in half an hour" means now plus that
   duration.
2. **Otherwise `NSDataDetector` (dates).**
   - If the matched text has a time, that date and time. A time already passed today with no explicit day
     moves to tomorrow.
   - If it has a day but no time ("on friday", "tomorrow"), that day at 9:00 AM.

The title:
- It's the transcript minus a leading "remind me to", "remind me", "set a reminder to", "add a reminder to",
  or "don't let me forget to".
- The matched time phrase is removed, plus a dangling "at", "on" or "in" before it.
- Surrounding whitespace and sentence punctuation are trimmed.
- It's nil if empty.

**`TimerParser.parse(_:) -> TimerRequest`**, where `TimerRequest { seconds: Int?; name: String? }`:
- **seconds:** the sum of every "N hour(s)/minute(s)/second(s)" part.
  - N can be digits, spelled out (using A's hyphen-first number parsing), "a"/"an" meaning 1, or "half an
    hour" meaning 1800.
  - "an hour and a half" is 5400. "90 seconds" is 90.
  - "pomodoro" with no duration is 1500.
- **name:**
  - the word(s) directly before "timer", excluding a, an, the, my, set, start, new, numbers and duration
    words ("pasta timer" → "pasta"; "10 minute timer" → nil)
  - "pomodoro" → "pomodoro" when no other name is given

**`TimerParser.target(_:) -> TimerTarget`**, for time-left and cancel, where
`TimerTarget = .all | .named(String) | .unspecified`:
- "all timers", "every timer" → `.all`
- a word before "timer" → `.named`
- otherwise → `.unspecified`

## 3. Actions

A third protocol in `SystemControls`:

```swift
public struct RelayTimer: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID; public let name: String?; public let endsAt: Date
}
public struct TimerStart: Sendable, Equatable { public let timer: RelayTimer; public let notificationsAllowed: Bool }

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

| Action | Mechanism | Permission |
|---|---|---|
| Type | `NSPasteboard`: save every item (all types and their data), write the text, then ⌘V (key code 9) via A's `KeyEvents.pressKey`. After 0.3 s, restore the saved items **only if** `changeCount` still equals the value right after Relay's write. The app in front is `NSWorkspace.frontmostApplication` excluding Relay (otherwise `.noFrontWindow`). If Relay has a key window, the front app is re-activated first, as in B | Accessibility |
| Note | `/usr/bin/osascript` through `ProcessRunner` (15 s timeout). Call 1: `on run argv` gets the body of the note named "Relay" (creating it if missing). Swift then builds `NoteBody.prepend(...)`. Call 2 sets the body, passed as an argument. stderr containing −1743 → `.automationDenied("Notes")` | Automation (Notes) |
| Reminder | `EKEventStore.requestFullAccessToReminders()`, then an `EKReminder` in `defaultCalendarForNewReminders()`. With `due`, set `dueDateComponents` and add an `EKAlarm(absoluteDate: due)`. Denied → `.remindersDenied`; no default list → `.failed("no default Reminders list")` | Reminders (full access) |
| Timers | `TimerStore` (§3.2) plus `NotificationScheduling` (§3.3) | Notifications |

### 3.1 Note body

`NoteBody.prepend(entry: String, at date: Date, to body: String?) -> String` builds an HTML body:
- The first element is the title `<div><h1>Relay</h1></div>`.
- The new line is `<div>MMM d, HH:mm — <escaped entry></div>`, with `&`, `<` and `>` escaped, and goes
  directly after the title.
- Everything that followed the title before stays after the new line.
- A nil or empty body produces the title plus the one line.

`NoteScript` holds the two AppleScript sources and turns `osascript` results into values:
- `readArguments() -> [String]`: the arguments that read (and if needed create) the "Relay" note and print
  its body.
- `writeArguments(body:) -> [String]`: the arguments that set the body, which is passed as an argument
  rather than inserted into the script.
- `interpret(_ result: CommandResult) throws -> String`: the body text on success; `-1743` in stderr →
  `.automationDenied("Notes")`; any other failure → `.failed(<stderr or "osascript exited N">)`.

### 3.2 Timer store

`TimerStore(fileURL:)` keeps `[RelayTimer]` as JSON in `~/Library/Application Support/Relay/timers.json`.
- `start(name:seconds:now:) -> RelayTimer`: if a running timer already has the name, the new one is named
  "<name> 2", "<name> 3", and so on.
- `active(now:) -> [RelayTimer]`: timers that haven't ended, soonest first.
- `remove(id:)`.
- `prune(now:)`: removes ended timers, and runs at launch.
- A missing or corrupt file reads as `[]`, and writes are atomic.

### 3.3 Notifications

`NotificationScheduling` is a protocol with a `UNUserNotificationCenter` implementation:
- `schedule(id:title:body:after:)` uses a `UNTimeIntervalNotificationTrigger` and the default sound.
- `cancel(id:)` removes the pending request.
- `allowed() async -> Bool` checks the authorization status.

Notification text:
- Title: "Timer done", or "<Name> timer done" ("Pasta timer done").
- Body: "<duration> is up", e.g. "9 minutes is up".

### 3.4 Errors

- `SystemControlError.automationDenied` becomes `automationDenied(String)`, carrying the app name. A's dark
  mode throws `automationDenied("System Events")` and B's Finder lookup throws `automationDenied("Finder")`.
  The existing messages and behaviour for both are unchanged.
- New case: `.remindersDenied`.

## 4. Assistant and UI

**New dependency and state:**
- `AssistantDependencies` gains `capture: any CaptureControlling`.
- `PermissionKind` gains `.reminders`, whose System Settings anchor is `Privacy_Reminders`.
- `Assistant` gains `timers: [RelayTimer]`. It's refreshed after every timer action and by
  `refreshTimers()`, which the panel calls when it appears.
- `Assistant` gains `cancelTimer(_ timer: RelayTimer) async`, used by the panel's ✕.

**Formatting** (pure, tested, in `AssistantCore`):
- **Durations:** "10 minutes", "1 minute", "1 hour 30 minutes", "1 minute 30 seconds", "45 seconds".
- **Remaining time:** "7 minutes 12 seconds left" for one timer. For several: "Pasta: 3 min left · Tea: 1 min
  left", with minutes rounded up, "<1 min" under a minute, and unnamed timers shown as "Timer".
- **Reminder times:** "today 5:00 PM", "tomorrow 9:00 AM", a weekday within the next 6 days ("Fri 9:00 AM"),
  otherwise "Oct 3 9:00 AM" (en_US_POSIX with a 12-hour clock).

**Messages:**

| Result | Message | Result type |
|---|---|---|
| Typed | "Typed into <App>" | success |
| No text | "What should I type?" | info |
| `.noFrontWindow` | "There's no app window in front to type into." | problem |
| Note saved | "Noted: <first 40 characters of the text, plus … if longer>" | success |
| Empty note | "What should the note say?" | info |
| Notes Automation denied | "Relay needs permission to control Notes to save notes." with Open System Settings (Automation) | problem |
| Note failed | "Couldn't save the note: <reason>" | problem |
| Reminder with a due date | "Reminder set: <title> — <reminder time>" | success |
| Reminder without one | "Reminder added: <title>" | success |
| Empty reminder title | "What should I remind you about?" | info |
| `.remindersDenied` | "Relay needs Reminders access to add reminders." with Open System Settings (Reminders) | problem |
| Reminder failed | "Couldn't add the reminder: <reason>" | problem |
| Timer started | "Timer set for <duration>" / "<Name> timer set for <duration>" | success |
| Timer started with notifications off | the above plus ", but notifications are off for Relay, so turn them on to hear it" | success |
| No duration | "How long? Try “10 minutes”." | info |
| Time left | the remaining-time text; "No timers running" when there are none | success / info |
| Cancel one | "Cancelled the <name> timer" / "Cancelled the timer" | success |
| Cancel all | "Cancelled N timers" | success |
| Cancel an unknown name | "No <name> timer running" | info |
| Cancel unspecified with several running | "Which timer? Pasta, Tea" | info |
| Cancel with none running | "No timers running" | info |

**Time-left targeting:** `.named` shows that timer only, and an unknown name gives "No <name> timer
running". `.unspecified` and `.all` show every timer.

**UI:**
- **Panel:** while `timers` isn't empty, a **Timers** section lists each timer's name and remaining time
  (updated every second through `TimelineView`) with a ✕ that calls `cancelTimer`. `AppController` calls
  `refreshTimers()` whenever it shows the panel.
- **`Info.plist`** gains `NSRemindersFullAccessUsageDescription` and `NSRemindersUsageDescription`: "Relay
  adds reminders you ask for to Apple Reminders."
- **At launch,** `AppController` asks the timer store to prune ended timers.

## 5. Testing

- **`CommandRulesTests`:**
  - positive phrases for all six intents, plus the spike held-outs: "type i'll be there in ten minutes",
    "write thank you so much", "note that the car needs servicing", "remind me at 8pm to take my medicine",
    "remind me on friday to submit the report", "timer for 3 minutes"
  - the §2.2 priority cases
  - all A and B tests still pass
- **Parser tests,** with a fixed `now` (2026-09-28 16:00, a Monday), the Gregorian calendar and a fixed time
  zone:
  - dictation keeps punctuation
  - note lead-ins
  - reminders: "at 5pm" → today 17:00; "at 3pm" → tomorrow 15:00; "tomorrow at 9" → 09:00 tomorrow; "on
    friday" → Friday 09:00; "in 20 minutes" → 16:20; no time → nil; title extraction
  - timer seconds and names, and `target`
- **`SystemControlsTests`:**
  - `NoteBody.prepend`: a new body, an existing body, and escaping
  - `TimerStore` against a real temporary file: start, active order, duplicate names, remove, prune, a
    corrupt file
  - `NoteScript` argument building, through a fake runner
- **`AssistantCoreTests`:** a fake `CaptureControlling` covers every §4 message row, the timer state refresh,
  and `cancelTimer`. The formatter tests cover durations, remaining time and reminder times.
- **`make test-routing`:** about 12 new phrases, with `minimumAccuracy` staying at 1.0.
- **Manual checklist:**
  - typing into TextEdit and a browser field, and the previous clipboard coming back
  - the Notes prompt, and dated lines at the top of the "Relay" note
  - the Reminders prompt, and a timed reminder alerting
  - a timer notification with sound, including after quitting Relay
  - named timers, time left, and cancel from the panel ✕

## 6. Out of scope

- Editing or deleting notes, reminders or other users' data. Recurring reminders. Choosing a Reminders list
  or Notes folder by voice.
- A live countdown in the pill or menu bar.
- Detecting that the app in front refused a paste.
