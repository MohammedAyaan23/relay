# Relay sub-project B: apps, windows, files, and more screenshots (design)

Date: 2026-09-28
Status: approved in conversation, awaiting written-spec review
Builds on: `2026-09-28-relay-mac-controls-design.md` (sub-project A, merged to `master`)

## 1. Purpose

Relay should manage apps, windows and files by voice, and take richer screenshots. It keeps A's
constraints: no new dependencies or models, small and quick, hotkey start and stop, and **non-destructive
only**. Nothing is deleted, overwritten or force-quit.

**Success:** each of these works first time and shows its result in the pill:
- "quit Slack", "close Spotify completely", "hide this app"
- "minimize this window", "make this full screen", "close the tab"
- "make a new folder called invoices", "create a text file called todo in Documents"
- "open the budget spreadsheet", "find my lease agreement", "show the Downloads folder in Finder"
- "screenshot this window", "copy a screenshot", "screenshot an area", "take a screenshot and show it"

**User decisions made in brainstorming:**
- **Screenshots:** add all four new kinds: front window, clipboard, pick an area, and open after.
- **Several file matches:** always show a list in the panel. Relay never guesses. One match is acted on
  directly.
- **Default location for new items:** the front Finder window's folder if Finder is the app in front,
  otherwise the Desktop.
- **Window actions:** standard shortcuts (⌘M, ⌃⌘F, ⌘W) sent to the app in front. Quit and hide use
  `NSRunningApplication`, not the Accessibility window API.

## 2. Routing

B extends A's `CommandRules` table. The evidence for rule-based routing is in A's spec (§2): the spike's
rule table, which included window and file phrases, routed 39 of 40 held-out phrases correctly.

### 2.1 New intents

New `RoutedIntent` cases, with their raw values:
`quitApp` ("quit_app"), `hideApp` ("hide_app"), `minimizeWindow` ("minimize_window"), `fullScreen`
("full_screen"), `closeWindow` ("close_window"), `createFolder` ("create_folder"), `createFile`
("create_file"), `findFile` ("find_file"), `openFile` ("open_file"), `revealFile` ("reveal_file").

Each gets a `displayName`. The Laya choice question is unchanged.

### 2.2 Rules

**File words:** file, files, document, documents, doc, pdf, spreadsheet, presentation, report, agreement,
contract, invoice, folder, directory. "photo" and "photos" are deliberately excluded, so "open Photos"
stays an app request for Laya.

**Global guards change:**
- A's `appLeadIns` guard (a transcript starting with "open" or "launch" skips the table) now applies **only
  when the transcript contains no file word**.
- So "open sound settings" and "open Safari" still go to Laya.
- And "open the budget spreadsheet" reaches the table.

**Table order:** A's `screenshot` first, then B's rules below, then A's remaining rules (lock, darkMode,
focus, brightness, volume, previous, next, play/pause).

| # | Intent | anyOf | alsoAnyOf | startsWith | noneOf |
|---|---|---|---|---|---|
| B1 | `quitApp` | quit, exit | | quit, exit | playing, music, full screen |
| B2 | `quitApp` | close | completely | | |
| B3 | `hideApp` | hide | | hide | |
| B4 | `minimizeWindow` | minimize, minimise | | | |
| B5 | `fullScreen` | full screen, fullscreen | | | |
| B6 | `closeWindow` | close | window, tab, this, it | | completely |
| B7 | `quitApp` | close | | close | window, tab, this, it |
| B8 | `createFolder` | folder, directory | create, make, new, add | | |
| B9 | `createFile` | *file words except folder/directory* | create, make, new | | |
| B10 | `revealFile` | finder, reveal | | | |
| B11 | `findFile` | where is, where did, where s, locate | | | |
| B12 | `findFile` | find | *file words* | | |
| B13 | `openFile` | open | *file words* | open | |

**Note on B7:** "close Spotify" is a quit. "close the door" also becomes `quitApp`, but it finds no running
app called "door" and says so. That's harmless.

**A's `screenshot` rule** matches the new screenshot phrasings as well: "screenshot this window", "copy a
screenshot", "screenshot an area".

### 2.3 Detail parsers (in `Extraction`, pure)

**`AppTargetParser.parse(_:) -> AppTarget`**, where `AppTarget = .frontmost | .named(String)`:
- It removes lead-ins (quit, exit, close, hide), and the words completely, the, app, application, please.
- If nothing is left, or only "this" or "this window", the result is `.frontmost`.
- Otherwise the rest is the name, which is matched against running apps with the existing `AppMatcher`.

**`FileRequestParser.parse(_:) -> FileRequest`**, where
`FileRequest { name: String?; location: FileLocation?; fileExtension: String? }` and
`FileLocation = .desktop | .documents | .downloads | .home`:

- **name:**
  - If the transcript contains "called" or "named", the name is the words after it, up to a location
    phrase.
  - Otherwise it's `nil` (Relay then asks "What should the folder be called?").
  - Spoken "dot" joins the extension: "notes dot md" → name "notes", extension "md".
- **location:** "on/in (the) desktop", "in (my) documents", "in (my) downloads", "in (my) home (folder)".
- **fileExtension:** a spoken "dot xyz", or `nil`. `createFile` then defaults to "txt"; "text file" also
  means "txt".

**`FileRequestParser.query(_:) -> String?`** builds the search text for find, open and reveal:
- It removes lead-ins (open, find, where is, where did i put, locate, show, reveal, in finder), filler words
  (my, the, a, an, that, this, please, i), and file words.
- If the result would be empty but the transcript contained a file word, that word is kept ("open the
  invoice" → "invoice").
- It returns `nil` if nothing is left.
- A named location ("show the downloads folder in finder") is detected separately by `parse`.

**`ScreenshotOptionsParser.parse(_:) -> ScreenshotOptions`**, where
`ScreenshotOptions { target: .screen | .window | .area; toClipboard: Bool; openAfter: Bool }`:
- **target:** "window" → `.window`. "area", "region", "part of the screen", "select", "selection" →
  `.area`. Otherwise `.screen`.
- **toClipboard:** "copy", "clipboard".
- **openAfter:** "and show it", "and open it", "show me", "open it".
- If `toClipboard` is set, `openAfter` is ignored, because there's no file to open.

## 3. Actions

A second protocol in `SystemControls`, so the assistant can be tested with a fake:

```swift
public enum WindowShortcut: Sendable, Equatable { case minimize, fullScreen, close }  // ⌘M, ⌃⌘F, ⌘W
public enum ScreenshotResult: Sendable, Equatable { case saved(URL), copied, cancelled }
public struct FileMatch: Sendable, Equatable { public let name: String; public let url: URL; public let lastUsed: Date? }

public protocol WorkspaceControlling: Sendable {
    func runningApps() async -> [InstalledApp]            // regular apps, excluding Relay
    func frontmostAppName() async -> String?              // nil when Relay itself is in front
    func quit(appNamed name: String) async throws          // normal Quit (apps may ask to save)
    func hide(appNamed name: String) async throws
    func sendWindowShortcut(_ shortcut: WindowShortcut) async throws
    func frontFinderFolder() async throws -> URL?          // nil unless Finder is in front with a window
    func createFolder(named name: String, in folder: URL) async throws -> URL
    func createFile(named name: String, in folder: URL) async throws -> URL
    func searchFiles(_ query: String) async throws -> [FileMatch]   // ranked, at most 8
    func open(_ url: URL) async throws
    func reveal(_ url: URL) async throws
    func captureScreenshot(_ options: ScreenshotOptions) async throws -> ScreenshotResult
}
```

**Screenshots move.** A's `SystemControlling.takeScreenshot()` is removed. All screenshots, including A's
plain whole-screen one, now go through `captureScreenshot`. A's tests and fake are updated to match.

| Action | Mechanism | Permission |
|---|---|---|
| Quit / hide | `NSWorkspace.runningApplications` → `terminate()` / `hide()` | none |
| Window shortcuts | CGEvent key presses to the app in front: ⌘M (key code 46), ⌃⌘F (key code 3), ⌘W (key code 13) | Accessibility |
| Front Finder folder | `NSAppleScript` to Finder: the POSIX path of the front Finder window's target. Used only when Finder is the frontmost app | Automation (Finder) |
| Create | FileManager, with `UniqueName` finding the first free name (§3.1) | none |
| Search | `mdfind -onlyin <home> -name <query>` through A's `ProcessRunner` (15 s timeout), then filtered and ranked (§3.2) | none |
| Open / reveal | `NSWorkspace.open` / `activateFileViewerSelecting` | none |
| Screenshot | `screencapture` with arguments from `ScreenshotCommand` (§3.3). The window ID comes from `CGWindowListCopyWindowInfo` via `WindowList` (§3.3) | Screen Recording |

### 3.1 Unique names

`UniqueName.available(for name: String, in folder: URL) -> URL` returns the first free name: "invoices",
then "invoices 2", "invoices 3", and so on. For files it keeps the extension: "todo.txt", "todo 2.txt".
Nothing is ever overwritten.

### 3.2 Search filtering and ranking

`FileSearch.rank(paths: [String], query: String, home: URL, lastUsed: (URL) -> Date?) -> [FileMatch]`
does the following:

- **Drops** paths under `<home>/Library/`, paths with a component starting with ".", and paths inside `.app`
  bundles.
- **Ranks** by how the name (without its extension) matches the query, compared case-insensitively:
  1. exact match
  2. starts with the query
  3. contains the query
- **Breaks ties** by most recently used, from the file's content access date.
- **Keeps** the top 8.

### 3.3 Screenshot commands

**`ScreenshotCommand.arguments(for options: ScreenshotOptions, file: URL?, windowID: Int?) -> [String]`:**

| Options | Arguments |
|---|---|
| screen → file | `["-x", path]` |
| window → file | `["-x", "-l", "<id>", path]` |
| area → file | `["-x", "-i", "-s", path]` |
| screen → clipboard | `["-x", "-c"]` |
| window → clipboard | `["-x", "-c", "-l", "<id>"]` |
| area → clipboard | `["-x", "-c", "-i", "-s"]` |

- The **file path** uses A's `ScreenshotLocation`. For window and area shots the name begins "Screenshot"
  as well, so all three look alike.
- **Area shots** run with a 60 s timeout, because the user is dragging. All other shots keep 15 s.
- **Result:** exit status 0 with the file present means `.saved(url)`. Exit status 0 with no file (Esc
  pressed) means `.cancelled`. A clipboard shot with exit status 0 means `.copied`; a cancelled area shot to
  the clipboard can't be detected, so it reports "copied".

**`WindowList.frontWindowID(pid: pid_t, windows: [[String: Any]]) -> Int?`** takes the on-screen window
list in front-to-back order. It returns the first window whose owner is `pid`, has layer 0 and is not
"Relay". If there's none, the action throws `.noFrontWindow`.

### 3.4 Errors

`SystemControlError` gains three cases:
- `.appNotRunning(String)`
- `.noFrontWindow`
- `.searchFailed(String)`

Existing cases are reused for permissions: `.accessibilityDenied` and `.screenRecordingDenied`.

**Finder Automation denied** (AppleScript −1743) is *not* an error for the user. `frontFinderFolder` throws
`.automationDenied`, and the assistant falls back to the Desktop, adding a note to the message (§4).

## 4. Assistant and UI

**New dependency and state:**
- `AssistantDependencies` gains `workspace: any WorkspaceControlling`.
- `Assistant` gains `fileMatches: [FileMatch]` and `fileMatchAction: FileMatchAction` (`.open` or
  `.reveal`). Both are cleared when listening starts.
- `Assistant` gains `pick(_ match: FileMatch) async`, which opens or reveals the match. If the file no
  longer exists: "That file is no longer there.", and the list stays.

**Resolving the target app:**
- `.frontmost` uses `frontmostAppName()`. If that's `nil`, the result is `.noFrontWindow`.
- `.named(name)` runs `AppMatcher(apps: runningApps())`. A match goes to that app. No match gives
  "<name> isn't running.", plus the closest running apps.

**Resolving where to create:**
1. An explicit location wins.
2. Otherwise `frontFinderFolder()` is used.
3. Otherwise the Desktop.
4. If `frontFinderFolder()` throws `.automationDenied`, Relay uses the Desktop and adds the Finder note.

**Messages:**

| Result | Message | Result type |
|---|---|---|
| Quit / hide | "Quit Slack" / "Hid Slack" | success |
| Window shortcut | "Minimized Safari" / "Toggled full screen" / "Closed window" | success |
| Create folder | "Created folder “invoices” on Desktop" (the actual final name, e.g. "invoices 2") | success |
| Create file | "Created “todo.txt” in Documents" | success |
| Created after Finder Automation was denied | the above plus " (allow Relay to control Finder to use the open Finder window)" | success |
| No name given | "What should the folder be called?" / "What should the file be called?" | info |
| One match for open | open it; "Opened “Budget 2026.xlsx”" | success |
| One match for find or reveal | reveal it; "Showed “lease.pdf” in Finder" | success |
| Several matches | "Found 4 files matching “tax”. Pick one in the panel." Sets `fileMatches` | info |
| No matches | "No files matching “tax”." | info |
| No search text | "Which file?" | info |
| Named place to reveal ("show the Downloads folder in Finder") | reveal that folder; "Showed Downloads in Finder" | success |
| Screenshot saved | "Screenshot saved to Desktop" / "Window screenshot saved to Desktop" / "Area screenshot saved to Desktop". With `openAfter`, the file is then opened | success |
| Screenshot copied | "Screenshot copied to clipboard" (plus "Window " / "Area " prefixes) | success |
| Screenshot cancelled | "Screenshot cancelled" | info |
| `.appNotRunning(n)` | "<n> isn't running." (plus " Running: A, B, C." when the name didn't match) | problem |
| `.noFrontWindow` | "There's no app window in front to <minimize / make full screen / close / quit / hide / capture>." | problem |
| `.searchFailed(r)` | "Couldn't search your files: <r>" | problem |
| Create failed | "Couldn't create “<name>”: <reason>" | problem |

Permission errors use A's existing messages and panel buttons.

**UI:**
- **Panel:** when `fileMatches` isn't empty, a **Pick a file** section lists each match: the name, then its
  folder path dimmed and shortened with `~`. Clicking a match calls `assistant.pick(_:)`.
- **Auto-open:** `AppController`'s watcher also opens the panel when `fileMatches` becomes non-empty.
- **Pill:** no visual changes.

## 5. Testing

- **`CommandRulesTests`:**
  - positive phrases for each new intent
  - collision phrases: "open Safari" and "open sound settings" → nil (Laya); "open the budget spreadsheet" →
    `openFile`; "find out who won the match" → nil (web); "quit playing music" → not `quitApp`; "close
    this window" → `closeWindow`; "close spotify completely" → `quitApp`; "close spotify" → `quitApp`
  - all of A's rule tests still pass, except that four phrases in A's "left to Laya" list are now B
    commands and move to B's positive tests: "find my resume file" (`findFile`), "open the budget
    spreadsheet" (`openFile`), "quit chrome" (`quitApp`), "go into full screen mode" (`fullScreen`)
  - the spike's held-out window and file phrases: "quit chrome", "hide slack", "minimise safari", "go into
    full screen mode", "close this tab please", "create a folder called receipts in downloads", "make a new
    text file named ideas", "find the lease agreement", "open the budget spreadsheet", "show my desktop
    folder in finder"
- **Parser tests:** tables for `AppTargetParser`, `FileRequestParser.parse` and `.query`, and
  `ScreenshotOptionsParser`.
- **`SystemControlsTests`:**
  - `UniqueName` against a real temporary folder, for files and folders
  - `FileSearch.rank`: filtering, the three match tiers, date tie-breaks, and the top-8 limit
  - `ScreenshotCommand.arguments`: all six rows of §3.3
  - `WindowList.frontWindowID`: owner, layer and Relay exclusion
- **`AssistantCoreTests`:** a fake `WorkspaceControlling` records calls. The tests cover:
  - every intent's call, message and result type
  - the one, several and no-match flows, including `fileMatches` being set and then cleared when listening
    starts, and `pick` on a file that has disappeared
  - the create-location order, including the Finder Automation fallback note
  - every error row in §4
  - A's screenshot tests, moved to `captureScreenshot`
- **`make test-routing`:** about 15 new phrases, with `minimumAccuracy` staying at 1.0.
- **Manual checklist:**
  - quitting an app with unsaved work shows its save prompt
  - ⌘M, ⌃⌘F and ⌘W each act on the app in front
  - creating inside a front Finder window (after the Finder Automation prompt) and on the Desktop
  - name clashes give "invoices 2"
  - the file list appears and clicking a result works
  - "open" with a single match opens it
  - window, area (drag, and Esc to cancel), clipboard (paste it somewhere) and "show it" screenshots

## 6. Out of scope

- Deleting, moving, renaming or overwriting anything; force-quitting.
- Typing, notes, reminders and timers (sub-project C).
- Choosing among several windows of the same app, and multi-display screenshot selection.
- Searching outside the home folder, and searching file contents (only names are searched).
