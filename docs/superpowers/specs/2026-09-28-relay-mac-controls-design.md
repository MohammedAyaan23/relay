# Relay sub-project A: rule routing plus Mac and media controls (design)

Date: 2026-09-28
Status: approved in conversation, awaiting written-spec review
Builds on: `2026-09-24-relay-voice-assistant-design.md` (Relay v1)

## 1. Purpose

Relay should handle many more everyday tasks from natural speech, while staying small and quick on any
Apple Silicon Mac running macOS 26. It must add no new model downloads and no third-party dependencies.
The hotkey trigger (press to start, press to stop) stays exactly as in v1.

The wider effort is split into three sub-projects, each with its own spec, plan and working result:

- **A (this spec):** a rule-based routing layer plus Mac and media controls.
- **B:** apps, windows and files. Quit, hide, minimize, full screen, close window; create, find, open and
  reveal files.
- **C:** typing and quick capture. Dictate into the frontmost app; notes (Apple Notes), reminders (Apple
  Reminders) and timers.

B and C reuse A's rule table and detail parsers.

**Success for A:** with any app in front, each of these works first time and shows its result in the pill:
- "turn the volume up", "set volume to 40 percent", "mute", "it's too loud"
- "make the screen brighter", "brightness to 70 percent"
- "switch to dark mode", "turn on do not disturb", "lock my Mac", "take a screenshot"
- "pause", "next song", "previous track"

**Safety rule for all sub-projects (user decision):** non-destructive only. Nothing is deleted or
overwritten, and nothing is force-quit.

## 2. Evidence behind the routing design

Measured on 2026-09-28 in the throwaway `spike/` prototype, using 65 phrases, plus 40 held-out phrases
written *before* any rules:

| Approach | Result | Latency |
|---|---|---|
| Laya: 8-way category choice, then a per-category choice | 33/65 | ~10 ms |
| Laya: one yes/no question per action (≈30 questions), pick the highest | 19/65 | ~100 ms |
| Apple `NLEmbedding` sentence embeddings, nearest 3 examples | 44/65 | ~2 ms |
| **Keyword rule table, then the v1 Laya gate + 3-way choice** | **64/65; held-out 39/40** | **< 1 ms** |

Findings:
- Laya is reliable for small decisions ("is this a command?", and choosing among open app, web search and
  ask Claude), and unreliable for many-way intent choice. Its yes/no answers say "yes" to almost any
  question about a short command.
- An 8-option Laya question with descriptive options is 180 tokens, which overflows the 128-token bucket
  (`promptTooLong`). Laya questions must stay small.
- Device commands are lexical: people say "volume", "mute", "screenshot", "remind me". Rules matched 37 of
  the 40 held-out phrases, all correctly. The only misses in the full pipeline were one out-of-vocabulary
  paraphrase and one piece of small talk that passed the gate.
- Embeddings added nothing once the rules were in place, so they are not part of the design.

**Known limit:** a phrasing that uses no rule vocabulary ("I can't hear anything") falls through to Laya's
3-way choice and can be misrouted. Mitigations: the pill always shows what Relay decided, and the decision
log is the source for new vocabulary.

## 3. Routing

The order in `LayaRouter.route`, where each step sees only what earlier steps didn't claim:

1. `SessionResetRule` (unchanged from v1).
2. **`CommandRules` (new):** an ordered rule table. The first match wins. If there's a match, Laya is not
   called.
3. The Laya gate, then Laya's 3-way choice (unchanged): `open_app` / `web_search` / `ask_claude`, or not a
   command.

### 3.1 Rule table

Transcripts are matched on normalized words: lowercased, with punctuation turned into spaces. Each entry
has:
- **action**
- **anyOf:** phrases, at least one of which must appear as whole words
- **startsWith (optional):** phrases the transcript must begin with
- **noneOf (optional):** phrases that must not appear

**Global guards**, checked before the table:
- A transcript mentioning "claude" skips the table ("tell Claude to mute the tests" goes to ask_claude).
- A transcript starting with a web-search lead-in ("search", "google", "look up", "find out") skips the
  table ("search for sound effects" goes to web_search).

The entries for sub-project A, in order:

| # | Action | anyOf | startsWith | noneOf |
|---|---|---|---|---|
| 1 | `screenshot` | screenshot, screen shot, screen capture, capture the screen | | |
| 2 | `lock` | lock | | |
| 3 | `darkMode` | dark mode, light mode, dark theme, light theme, appearance | | |
| 4 | `focus` | do not disturb, focus, notifications, silence my mac | | |
| 5 | `brightness` | brightness, brighter, dimmer, dim, too bright, too dark | | |
| 6 | `volume` | volume, louder, quieter, mute, unmute, too loud, sound | | |
| 7 | `mediaPrevious` | previous, last track, last song, back a song, back a track | | |
| 8 | `mediaNext` | next, skip | *(see note)* | |
| 9 | `mediaPlayPause` | play, pause, resume, unpause, stop the music, stop playing, stop the song | | open, launch, *document nouns* |

**Note for #8:** it matches when the transcript *starts with* "next" or "skip", or when it contains "next"
or "skip" together with "song", "track" or "one". So "my brother is visiting next week" does not match.

**Document nouns** are: file, files, document, pdf, spreadsheet, presentation, report, agreement, contract,
invoice, resume. They stop "find my resume file" from being read as "resume playback".

**New `RoutedIntent` cases:** `volume`, `brightness`, `darkMode`, `focus`, `lock`, `screenshot`,
`mediaPlayPause`, `mediaNext`, `mediaPrevious`, each with a `displayName`. The Laya choice question is
unchanged; it still offers only the three v1 options. A rule match returns
`RoutingDecision(outcome: .intent(x), gateProbability: 1, choiceProbabilities: [x: 1], stateWasTruncated: false)`,
the same shape as `SessionResetRule`.

### 3.2 Detail parsers (in `Extraction`, pure functions)

**`LevelParser.parse(_ transcript:) -> LevelCommand?`**, where
`LevelCommand = .set(Int) | .up(Int) | .down(Int) | .mute | .unmute`:

- **Absolute:** "40 percent", "40%", "to 40", "forty percent" → `.set(40)`.
  - Spoken numbers are handled by `NumberFormatter` with `.spellOut` style.
  - "half" → 50.
  - "max", "maximum", "all the way up", "full" → 100.
  - "min", "minimum", "all the way down" → 0.
  - Values are clamped to 0…100.
- **Relative:**
  - Up words: up, louder, brighter, raise, increase, crank, turn up, too dark, too quiet.
  - Down words: down, quieter, dimmer, dim, lower, decrease, reduce, turn down, too loud, too bright.
  - The default step is 10. With "a bit", "a little" or "slightly", the step is 6.
- **Mute:** "mute", "silence the sound" → `.mute`; "unmute" → `.unmute`. This takes priority over relative
  words.
- **Nothing recognised:** returns nil. The action then asks: "What volume? Try a percentage, like 40
  percent."

**`SwitchParser.parse(_ transcript:) -> SwitchCommand`**, where `SwitchCommand = .on | .off | .toggle`:

- "on", "enable", "start", "turn on", "switch to" → `.on`.
- "off", "disable", "stop", "turn off" → `.off`.
- **For dark mode, "light mode" or "light theme" inverts the result.** "switch to light mode" and "turn
  on light mode" mean dark mode off. "turn off light mode" means dark mode on.
- Anything else → `.toggle`.

## 4. Actions (new `SystemControls` module)

`SystemControls` has no UI. The assistant uses it through a protocol so tests can inject a fake:

```swift
public protocol SystemControlling: Sendable {
    func volume() async throws -> Int                              // 0…100
    func setVolume(_ percent: Int) async throws
    func setMuted(_ muted: Bool) async throws
    func setBrightness(percent: Int) async throws                  // Shortcuts bridge
    func stepBrightness(up: Bool, presses: Int) async throws       // brightness keys
    func setFocus(on: Bool) async throws                           // Shortcuts bridge
    func setDarkMode(_ mode: SwitchCommand) async throws           // AppleScript
    func lockScreen() async throws                                 // ⌃⌘Q keystroke
    func pressMediaKey(_ key: MediaKey) async throws               // .playPause / .next / .previous
    func takeScreenshot() async throws -> URL
}
```

| Action | Mechanism | Permission (requested on first use) |
|---|---|---|
| Volume | CoreAudio default output device: virtual main volume (scalar 0…1) and the mute property. Relative "up" also unmutes | none |
| Brightness set to N% | Shortcuts bridge: `shortcuts run "Relay Brightness" -i <temp file containing N>` | one-time shortcut import |
| Brightness up/down | system brightness key events. "up"/"down" is 2 presses, "a bit" is 1 press (each ≈ 1/16) | Accessibility |
| Focus on/off | Shortcuts bridge: `shortcuts run "Relay Focus" -i <temp file containing on/off>`, sets Do Not Disturb | one-time shortcut import |
| Dark mode | `NSAppleScript`: `tell application "System Events" to tell appearance preferences to set dark mode to <true/false/not dark mode>` | Automation (System Events) |
| Lock | posts ⌃⌘Q key events, the system Lock Screen shortcut | Accessibility |
| Media | posts system-defined media-key events (play/pause, next, previous), the same as the keyboard keys, so they control whatever is Now Playing. Play and pause are one toggle | Accessibility |
| Screenshot | `/usr/sbin/screencapture -x "<folder>/Screenshot <yyyy-MM-dd 'at' HH.mm.ss>.png"`, where `<folder>` is `defaults read com.apple.screencapture location` or `~/Desktop` if unset | Screen Recording |

**Why not other routes:**
- `pmset displaysleepnow` doesn't lock immediately when the Mac's screen-lock delay is above zero. This
  machine's delay is 60 s.
- Brightness and Focus have no public API. Siri uses private frameworks.
- The Shortcuts app's own "Set Brightness" and "Set Focus" actions are the public route.

**Accepted limitation:** media commands can't pick specific content ("play some jazz" just toggles
playback).

### 4.1 Shortcuts bridge

- Relay ships two signed shortcut files, `Resources/Shortcuts/Relay Brightness.shortcut` and
  `Resources/Shortcuts/Relay Focus.shortcut`, signed with `shortcuts sign --mode anyone`.
  `scripts/make-app.sh` copies them into `Relay.app/Contents/Resources/Shortcuts/`, and Relay loads them
  through `Bundle.main`. These are the app's own resources, not a SwiftPM resource bundle.
- **Relay Brightness:** takes the input as a number, and sets brightness to input ÷ 100.
- **Relay Focus:** if the input is "on", it turns Do Not Disturb on; otherwise it turns it off.
- **Before running:** Relay checks `shortcuts list` (cached after the first successful check). If the
  shortcut is missing, it throws `.shortcutMissing(name)`.
- **Authoring:** the files are generated and signed during implementation, then verified by running them.
  Fallback if generating them proves unreliable: a 3-step guide (`docs/shortcuts-setup.md`) for building
  them in the Shortcuts app, and the panel links to that guide instead of offering Add Shortcut.

### 4.2 Errors

```swift
public enum SystemControlError: Error, Equatable {
    case noVolumeControl
    case shortcutMissing(String)
    case shortcutFailed(String, reason: String)
    case automationDenied
    case accessibilityDenied
    case screenRecordingDenied
    case failed(String)
}
```

How each is detected:
- **Accessibility:** `AXIsProcessTrustedWithOptions`, with the system prompt on the first request.
- **Screen Recording:** `CGPreflightScreenCaptureAccess`, then `CGRequestScreenCaptureAccess` on the first
  request.
- **Automation:** AppleScript error −1743.

## 5. Assistant and UI changes

**Assistant (`AssistantCore`):**
- `AssistantDependencies` gains `system: any SystemControlling`.
- `Assistant.perform` handles the nine new intents, using the parsers from §3.2.
- New observable state:
  - `resultLevel: Double?`, 0…1. It's set for volume results and for brightness `.set`, and cleared when
    listening starts.
  - `missingShortcut: String?`, the name of the shortcut to import.
- `PermissionKind` gains `.accessibility`, `.screenRecording` and `.automation`.
- A permission failure during an action sets `missingPermission` and a message, then returns to idle.
  Unlike v1's microphone permission, this does not stay in `.preparing`.

**Result messages** (the result type is shown in brackets):

| Result | Message |
|---|---|
| Volume set, up or down (success) | "Volume 40%" |
| Mute / unmute (success) | "Muted" / "Unmuted" |
| Brightness set (success) | "Brightness 70%" |
| Brightness up / down (success) | "Brighter" / "Dimmer" |
| Dark mode (success) | "Dark mode on" / "Dark mode off" / "Switched appearance" |
| Focus (success) | "Do Not Disturb on" / "Do Not Disturb off" |
| Lock (success) | "Locking…" |
| Media (success) | "Play/Pause" / "Next track" / "Previous track" |
| Screenshot (success) | "Screenshot saved to <folder name>" |

**Error messages:**

| Error | Result type | Message | Panel |
|---|---|---|---|
| `noVolumeControl` | problem | "This audio device doesn't allow volume control." | — |
| `shortcutMissing(n)` | info | "<Brightness/Focus> needs a one-time setup." | opens with **Add Shortcut** |
| `shortcutFailed(n, r)` | problem | "The <n> shortcut failed: <r>" | — |
| `automationDenied` | problem | "Relay needs permission to control System Events for dark mode." | opens with **Open System Settings** (Automation) |
| `accessibilityDenied` | problem | "Relay needs Accessibility access to press keys for you." | opens with **Open System Settings** (Accessibility) |
| `screenRecordingDenied` | problem | "Relay needs Screen Recording permission to take screenshots." | opens with **Open System Settings** (Screen Recording) |
| level not understood | info | "What volume? Try a percentage, like 40 percent." ("What brightness? …" for brightness) | — |
| `failed(r)` | problem | "Couldn't <do action>: <r>" | — |

**Settings links:** `openPrivacySettings` gains the anchors `Privacy_Accessibility`,
`Privacy_ScreenCapture` and `Privacy_Automation`.

**UI (`RelayApp`):**
- **HUD:** when `resultLevel` is set, the result pill shows a small capsule level bar next to the message.
  It fills to the level with a spring animation, like macOS's own volume overlay.
- **Panel:** when `missingShortcut` is set, the panel shows **Add Shortcut**, which opens the bundled
  `.shortcut` file.
- **Auto-open:** the panel opens by itself when `missingShortcut` is set. This is in addition to the v1
  triggers: a Claude job, `missingPermission` and `prepareFailed`.
- **`Info.plist`** gains `NSAppleEventsUsageDescription`: "Relay controls System Events to switch dark
  mode when you ask."

## 6. Testing

- **`CommandRulesTests`:**
  - positive and negative phrases for every action
  - the collision cases: "find my resume file" is not media; "tell Claude to mute the tests" is
    ask_claude; "search for sound effects" is not volume; "my brother is visiting next week" is not next
    track; "unlock" is not lock
  - the spike's held-out phrases that belong to sub-project A, as a permanent regression test that needs
    no model
- **`LevelParserTests` / `SwitchParserTests`:** tables covering digits, "%", spoken numbers, half, max,
  min, "a bit", mute/unmute priority, light-mode inversion, and toggle.
- **`ShortcutsBridgeTests`:** a fake command runner checks argument building, the input temp file
  contents, the cached `shortcuts list` check, `.shortcutMissing`, and a non-zero exit becoming
  `.shortcutFailed`.
- **`AssistantCoreTests`:** a fake `SystemControlling` records calls. For each of the nine intents, the
  tests check the call and its values, the message, the result type and `resultLevel`. They also cover
  every §5 error row, including `missingPermission`/`missingShortcut` being set and the phase returning to
  idle.
- **`make test-routing`:** `phrases.json` gains at least 20 Mac and media phrases. The baseline stays at
  100% (the rules take the new ones, and Laya keeps the old 14).
- **Manual checklist** (`docs/manual-checklist.md`), one item per action:
  - the real volume changes, and the level bar animates
  - brightness set and step
  - dark mode switches, after the Automation prompt
  - Do Not Disturb turns on (visible in Control Center)
  - lock locks
  - media keys control Music and a YouTube tab
  - a screenshot lands in the screenshot folder, after the Screen Recording prompt
  - Add Shortcut imports the shortcut
  - Relay asks for each permission once, and the action works after it's granted

## 7. Out of scope for A

- Apps, windows and files (sub-project B); typing, notes, reminders and timers (sub-project C).
- External-display brightness (DDC), Focus modes other than Do Not Disturb, and choosing specific media
  content.
- Hands-free triggering (a wake phrase). The user chose to keep the hotkey for now.
- Embedding or LLM-based routing.
