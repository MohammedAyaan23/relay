# Relay Sub-project B (Apps, Windows, Files, More Screenshots) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relay quits, hides, minimizes, full-screens and closes windows, creates, finds, opens and reveals files, and takes window, area and clipboard screenshots with an optional "show it", all by voice and non-destructively.

**Architecture:**
- **Routing:** B's rules go into A's `CommandRules` table, after `screenshot` and before A's other rules. A's "open/launch" guard is narrowed.
- **Details:** new pure parsers in `Extraction`.
- **Actions:** a second protocol, `WorkspaceControlling`, in `SystemControls`, with a real `MacWorkspaceControls` built from NSWorkspace, key events, AppleScript (Finder), `mdfind` and `screencapture`.
- **Screenshots move:** A's `takeScreenshot()` is replaced by `captureScreenshot(options)`.
- **Assistant and UI:** `AssistantCore` maps the intents; `RelayApp` adds a "Pick a file" list to the panel.

**Tech Stack:** Swift 6, macOS 26, Swift Testing, AppKit (NSWorkspace, NSRunningApplication), CoreGraphics (CGEvent, CGWindowList), NSAppleScript, `/usr/bin/mdfind`, `/usr/sbin/screencapture`. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-28-relay-apps-windows-files-design.md`

## Global Constraints

- Branch `relay-b-apps-files`; macOS 26; Swift 6; no new dependencies.
- Run tests through `make test` / `make test FILTER=<name>`. `make test-routing` must stay at `minimumAccuracy` 1.0.
- **Non-destructive only:** quit is `terminate()` (never `forceTerminate()`), create never overwrites (`UniqueName`), and nothing is deleted, moved or renamed.
- Relay never quits, hides or sends shortcuts to itself (it's excluded by bundle identifier).
- Timeouts: `ProcessRunner` 15 s by default; area screenshots 60 s.
- Search: `mdfind -onlyin <home> -name <query>`, at most 300 paths considered, top 8 returned.
- User-facing messages use the exact strings in the tasks (spec §4); tests compare them.
- End every commit message with: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

## Review Focus

1. **Creating something whose name already exists.** Expected: "invoices 2" (or "todo 2.txt"), and the existing item is untouched. Tests in Task 3 (logic) and Task 4 (real temporary folder).
2. **Spoken or dictated file names with extensions** ("notes dot md", "notes.md", "report dot pdf"). Expected: the extension is preserved for create and search. Tests in Task 1.
3. **A listed file is deleted before the user clicks it.** Expected: "That file is no longer there." and the list stays. Test in Task 5.
4. **Relay itself is the frontmost app** (after using its menu or panel). Expected: "There's no app window in front to …". Relay never hides, quits or shortcuts itself. Tests in Task 5; the exclusion is in Task 4's code.
5. **"open Photos" and other app names that look like file commands.** Expected: they stay with Laya's open-app route, not `openFile`. Test in Task 2.

---

### Task 1: Parsers for app targets, file requests and screenshot options

**Files:**
- Create: `Sources/Extraction/AppTargetParser.swift`
- Create: `Sources/Extraction/FileRequestParser.swift`
- Create: `Sources/Extraction/ScreenshotOptionsParser.swift`
- Test: `Tests/ExtractionTests/WorkspaceParserTests.swift`

**Interfaces:**
- Consumes: `TextNormalizer.normalize` (existing).
- Produces:
  - `public enum AppTarget: Equatable, Sendable { case frontmost, named(String) }`
  - `AppTargetParser.parse(_:) -> AppTarget`
  - `public enum FileLocation: String, Equatable, Sendable, CaseIterable { case desktop, documents, downloads, home }`
  - `public struct FileRequest: Equatable, Sendable { name: String?; location: FileLocation?; fileExtension: String?; init(name:location:fileExtension:) }`
  - `FileRequestParser.parse(_:) -> FileRequest`
  - `FileRequestParser.query(_:) -> String?`
  - `public struct ScreenshotOptions: Equatable, Sendable { enum Target { screen, window, area }; target; toClipboard; openAfter; init(target:toClipboard:openAfter:) }`
  - `ScreenshotOptionsParser.parse(_:) -> ScreenshotOptions`

- [ ] **Step 1: Write the failing tests**

`Tests/ExtractionTests/WorkspaceParserTests.swift`:
```swift
import Testing
@testable import Extraction

@Test(arguments: [
    ("quit slack", AppTarget.named("slack")),
    ("close spotify completely", .named("spotify")),
    ("quit visual studio code please", .named("visual studio code")),
    ("hide this app", .frontmost),
    ("hide", .frontmost),
    ("quit this window", .frontmost),
])
func appTargets(_ transcript: String, _ expected: AppTarget) {
    #expect(AppTargetParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("make a new folder called invoices", FileRequest(name: "invoices", location: nil, fileExtension: nil)),
    ("make a new folder called invoices on the desktop", FileRequest(name: "invoices", location: .desktop, fileExtension: nil)),
    ("create a folder named Tax Returns in my documents", FileRequest(name: "Tax Returns", location: .documents, fileExtension: nil)),
    ("create a text file called todo in downloads", FileRequest(name: "todo", location: .downloads, fileExtension: nil)),
    ("create a file called notes dot md", FileRequest(name: "notes", location: nil, fileExtension: "md")),
    ("create a file called notes.md in documents", FileRequest(name: "notes", location: .documents, fileExtension: "md")),
    ("make a new folder", FileRequest(name: nil, location: nil, fileExtension: nil)),
    ("show the downloads folder in finder", FileRequest(name: nil, location: .downloads, fileExtension: nil)),
])
func fileRequests(_ transcript: String, _ expected: FileRequest) {
    #expect(FileRequestParser.parse(transcript) == expected)
}

@Test(arguments: [
    ("open the budget spreadsheet", "budget"),
    ("find my lease agreement", "lease"),
    ("where is the tax document", "tax"),
    ("where did i put my passport scan", "passport scan"),
    ("reveal the invoice in finder", "invoice"),
    ("open the file report dot pdf", "report.pdf"),
    ("show the downloads folder in finder", "downloads"),
])
func searchQueries(_ transcript: String, _ expected: String) {
    #expect(FileRequestParser.query(transcript) == expected)
}

@Test func noSearchTextIsNil() {
    #expect(FileRequestParser.query("open it") == nil)
    #expect(FileRequestParser.query("find") == nil)
}

@Test(arguments: [
    ("take a screenshot", ScreenshotOptions(target: .screen, toClipboard: false, openAfter: false)),
    ("screenshot this window", ScreenshotOptions(target: .window, toClipboard: false, openAfter: false)),
    ("screenshot an area", ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)),
    ("screenshot part of the screen", ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)),
    ("copy a screenshot", ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false)),
    ("copy a screenshot of this window to the clipboard", ScreenshotOptions(target: .window, toClipboard: true, openAfter: false)),
    ("take a screenshot and show it", ScreenshotOptions(target: .screen, toClipboard: false, openAfter: true)),
    ("copy a screenshot and show it", ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false)),
])
func screenshotOptions(_ transcript: String, _ expected: ScreenshotOptions) {
    #expect(ScreenshotOptionsParser.parse(transcript) == expected)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=WorkspaceParserTests`
Expected: the build fails with `cannot find 'AppTargetParser' in scope`.

- [ ] **Step 3: Implement**

`Sources/Extraction/AppTargetParser.swift`:
```swift
public enum AppTarget: Equatable, Sendable {
    case frontmost
    case named(String)
}

/// Which app a quit/hide command means: a spoken name, or the app in front ("this app", nothing).
public enum AppTargetParser {
    static let dropWords: Set<String> = ["quit", "exit", "close", "hide", "completely", "the", "app",
                                         "application", "please", "down", "out", "of"]

    public static func parse(_ transcript: String) -> AppTarget {
        let words = TextNormalizer.normalize(transcript).split(separator: " ").map(String.init)
        let rest = words.filter { !dropWords.contains($0) }
        if rest.isEmpty || rest == ["this"] || rest == ["this", "window"] || rest == ["it"] { return .frontmost }
        return .named(rest.joined(separator: " "))
    }
}
```

`Sources/Extraction/FileRequestParser.swift`:
```swift
import Foundation

public enum FileLocation: String, Equatable, Sendable, CaseIterable {
    case desktop, documents, downloads, home
}

public struct FileRequest: Equatable, Sendable {
    public var name: String?
    public var location: FileLocation?
    public var fileExtension: String?

    public init(name: String?, location: FileLocation?, fileExtension: String?) {
        self.name = name
        self.location = location
        self.fileExtension = fileExtension
    }
}

/// Reads file commands: "make a folder called invoices on the desktop", "open the budget spreadsheet".
public enum FileRequestParser {
    static let fileWords: Set<String> = ["file", "files", "document", "documents", "doc", "pdf", "spreadsheet",
                                         "presentation", "report", "agreement", "contract", "invoice", "folder",
                                         "directory"]
    static let prepositions: Set<String> = ["in", "on", "inside", "into"]
    static let articles: Set<String> = ["the", "my"]
    static let searchDropWords: Set<String> = ["open", "find", "locate", "show", "reveal", "where", "is", "s",
                                               "did", "put", "save", "saved", "my", "the", "a", "an", "that",
                                               "this", "it", "please", "i", "me", "for", "in", "finder", "called",
                                               "named"]

    public static func parse(_ transcript: String) -> FileRequest {
        let words = tokens(transcript)
        let lower = words.map { $0.lowercased() }

        var nameWords: [String] = []
        if let marker = lower.firstIndex(where: { $0 == "called" || $0 == "named" }) {
            var i = marker + 1
            while i < words.count, !startsLocationPhrase(lower, at: i) {
                nameWords.append(words[i])
                i += 1
            }
        }
        var fileExtension: String?
        if let dot = nameWords.firstIndex(where: { $0.lowercased() == "dot" }), dot + 1 < nameWords.count {
            fileExtension = nameWords[dot + 1].lowercased()
            nameWords = Array(nameWords[..<dot])
        }
        let name = nameWords.isEmpty ? nil : nameWords.joined(separator: " ")
        return FileRequest(name: name, location: location(in: lower), fileExtension: fileExtension)
    }

    /// Search text for find/open/reveal: the transcript minus lead-ins, filler and file words.
    public static func query(_ transcript: String) -> String? {
        let lower = tokens(transcript).map { $0.lowercased() }
        var kept: [String] = []
        for (i, word) in lower.enumerated() {
            // The word after "dot" is an extension ("report dot pdf"), even if it's also a file word.
            let isExtension = i > 0 && lower[i - 1] == "dot"
            if isExtension || (!searchDropWords.contains(word) && !fileWords.contains(word)) { kept.append(word) }
        }
        var text = kept.joined(separator: " ")
        if text.isEmpty, let fileWord = lower.first(where: { fileWords.contains($0) && $0 != "file" && $0 != "files" }) {
            text = fileWord
        }
        text = text.replacingOccurrences(of: " dot ", with: ".")
        return text.isEmpty ? nil : text
    }

    /// Words with case kept; "notes.md" becomes "notes dot md" so spoken and typed extensions look alike.
    static func tokens(_ transcript: String) -> [String] {
        let dotted = transcript.replacing(/(\w)\.(\w)/) { "\($0.output.1) dot \($0.output.2)" }
        let spaced = String(dotted.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").map(String.init)
    }

    /// A location word counts after a preposition ("on the desktop") or before "folder" ("the downloads folder").
    static func location(in lower: [String]) -> FileLocation? {
        for (i, word) in lower.enumerated() {
            guard let place = FileLocation(rawValue: word) else { continue }
            let followedByFolder = i + 1 < lower.count && lower[i + 1] == "folder"
            if followedByFolder || precededByPreposition(lower, at: i) { return place }
        }
        return nil
    }

    static func precededByPreposition(_ lower: [String], at index: Int) -> Bool {
        var i = index - 1
        while i >= 0, articles.contains(lower[i]) { i -= 1 }
        return i >= 0 && prepositions.contains(lower[i])
    }

    static func startsLocationPhrase(_ lower: [String], at index: Int) -> Bool {
        guard prepositions.contains(lower[index]) else { return false }
        var i = index + 1
        while i < lower.count, articles.contains(lower[i]) { i += 1 }
        return i < lower.count && FileLocation(rawValue: lower[i]) != nil
    }
}
```

`Sources/Extraction/ScreenshotOptionsParser.swift`:
```swift
public struct ScreenshotOptions: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case screen, window, area
    }

    public var target: Target
    public var toClipboard: Bool
    public var openAfter: Bool

    public init(target: Target, toClipboard: Bool, openAfter: Bool) {
        self.target = target
        self.toClipboard = toClipboard
        self.openAfter = openAfter
    }
}

/// Reads screenshot variants: "screenshot this window", "copy a screenshot", "…and show it".
public enum ScreenshotOptionsParser {
    public static func parse(_ transcript: String) -> ScreenshotOptions {
        let padded = " \(TextNormalizer.normalize(transcript)) "
        func has(_ phrases: [String]) -> Bool { phrases.contains { padded.contains(" \($0) ") } }
        let target: ScreenshotOptions.Target =
            has(["area", "region", "part of the screen", "select", "selection"]) ? .area
            : has(["window"]) ? .window
            : .screen
        let toClipboard = has(["copy", "clipboard"])
        let openAfter = !toClipboard && has(["show it", "open it", "show me"])
        return ScreenshotOptions(target: target, toClipboard: toClipboard, openAfter: openAfter)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=WorkspaceParserTests`
Expected: all parser tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Extraction Tests/ExtractionTests
git commit -m "Add parsers for app targets, file requests and screenshot options" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rules and intents for apps, windows and files

**Files:**
- Modify: `Sources/Routing/RoutingTypes.swift` (10 new `RoutedIntent` cases)
- Modify: `Sources/Routing/CommandRules.swift` (file words, narrower guard, B rules)
- Modify: `Sources/AssistantCore/Assistant.swift` (temporary case, replaced in Task 5)
- Modify: `Tests/RoutingTests/CommandRulesTests.swift` (4 phrases leave A's "left to Laya" list)
- Modify: `Tests/RoutingTests/phrases.json` (15 phrases)
- Test: `Tests/RoutingTests/WorkspaceRulesTests.swift`

**Interfaces:**
- Consumes: `CommandRules.Rule`, `CommandRules.match` (A).
- Produces: `RoutedIntent` cases `quitApp`, `hideApp`, `minimizeWindow`, `fullScreen`, `closeWindow`, `createFolder`, `createFile`, `findFile`, `openFile`, `revealFile`.

- [ ] **Step 1: Write the failing tests**

`Tests/RoutingTests/WorkspaceRulesTests.swift`:
```swift
import Testing
@testable import Routing

@Test(arguments: [
    ("quit slack", RoutedIntent.quitApp),
    ("close spotify completely", .quitApp),
    ("close spotify", .quitApp),
    ("exit xcode", .quitApp),
    ("hide this app", .hideApp),
    ("minimize this window", .minimizeWindow),
    ("make this full screen", .fullScreen),
    ("exit full screen", .fullScreen),
    ("close this window", .closeWindow),
    ("close the tab", .closeWindow),
    ("make a new folder called invoices", .createFolder),
    ("create a text file called todo in documents", .createFile),
    ("open the budget spreadsheet", .openFile),
    ("find my lease agreement", .findFile),
    ("where is the tax document", .findFile),
    ("show the downloads folder in finder", .revealFile),
    ("screenshot this window", .screenshot),
    ("copy a screenshot", .screenshot),
    ("screenshot an area", .screenshot),
])
func workspaceCommandsMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

/// Held-out phrases from the 2026-09-28 routing spike (written before the rules existed).
@Test(arguments: [
    ("quit chrome", RoutedIntent.quitApp),
    ("hide slack", .hideApp),
    ("minimise safari", .minimizeWindow),
    ("go into full screen mode", .fullScreen),
    ("close this tab please", .closeWindow),
    ("create a folder called receipts in downloads", .createFolder),
    ("make a new text file named ideas", .createFile),
    ("find the lease agreement", .findFile),
    ("find my resume file", .findFile),
    ("open the budget spreadsheet", .openFile),
    ("show my desktop folder in finder", .revealFile),
])
func heldOutWorkspacePhrasesMatch(_ transcript: String, _ expected: RoutedIntent) {
    #expect(CommandRules.match(transcript) == expected)
}

@Test(arguments: [
    "open safari",
    "open photos",
    "open sound settings",
    "find out who won the match",
    "quit playing music",
])
func appAndWebRequestsStayWithLaya(_ transcript: String) {
    #expect(CommandRules.match(transcript) == nil)
}
```

In `Tests/RoutingTests/CommandRulesTests.swift`, in the `otherCommandsAreLeftToLaya` argument list, **remove** these four lines. They are now B commands, tested above:
```
    "find my resume file",
    "open the budget spreadsheet",
    "quit chrome",
    "go into full screen mode",
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=WorkspaceRulesTests`
Expected: the build fails with `type 'RoutedIntent' has no member 'quitApp'`.

- [ ] **Step 3: Add the intents**

In `Sources/Routing/RoutingTypes.swift`, add these cases to `RoutedIntent` after `case mediaPrevious = "media_previous"`:
```swift
    case quitApp = "quit_app"
    case hideApp = "hide_app"
    case minimizeWindow = "minimize_window"
    case fullScreen = "full_screen"
    case closeWindow = "close_window"
    case createFolder = "create_folder"
    case createFile = "create_file"
    case findFile = "find_file"
    case openFile = "open_file"
    case revealFile = "reveal_file"
```
and add these to the `displayName` switch after `case .mediaPrevious: "go to the previous track"`:
```swift
        case .quitApp: "quit an app"
        case .hideApp: "hide an app"
        case .minimizeWindow: "minimize the window"
        case .fullScreen: "toggle full screen"
        case .closeWindow: "close the window"
        case .createFolder: "create a folder"
        case .createFile: "create a file"
        case .findFile: "find a file"
        case .openFile: "open a file"
        case .revealFile: "show a file in Finder"
```

- [ ] **Step 4: Add the rules**

In `Sources/Routing/CommandRules.swift`:

1. After `static let questionWords = …`, add:
```swift
    /// Words that make a command about files; an "open…" command with one of these is a file request.
    static let fileWords = ["file", "files", "document", "documents", "doc", "pdf", "spreadsheet", "presentation",
                            "report", "agreement", "contract", "invoice", "folder", "directory"]
    static let fileWordsExceptFolders = fileWords.filter { $0 != "folder" && $0 != "directory" }
    static let windowWords = ["window", "tab", "this", "it"]
```
2. In `rules`, directly after the `screenshot` rule, add:
```swift
        Rule(intent: .quitApp, anyOf: ["quit", "exit"], startsWith: ["quit", "exit"],
             noneOf: ["playing", "music", "full screen"]),
        Rule(intent: .quitApp, anyOf: ["close"], alsoAnyOf: ["completely"]),
        Rule(intent: .hideApp, anyOf: ["hide"], startsWith: ["hide"]),
        Rule(intent: .minimizeWindow, anyOf: ["minimize", "minimise"]),
        Rule(intent: .fullScreen, anyOf: ["full screen", "fullscreen"]),
        Rule(intent: .closeWindow, anyOf: ["close"], alsoAnyOf: windowWords, noneOf: ["completely"]),
        Rule(intent: .quitApp, anyOf: ["close"], startsWith: ["close"], noneOf: windowWords),
        Rule(intent: .createFolder, anyOf: ["folder", "directory"], alsoAnyOf: ["create", "make", "new", "add"]),
        Rule(intent: .createFile, anyOf: fileWordsExceptFolders, alsoAnyOf: ["create", "make", "new"]),
        Rule(intent: .revealFile, anyOf: ["finder", "reveal"]),
        Rule(intent: .findFile, anyOf: ["where is", "where did", "where s", "locate"]),
        Rule(intent: .findFile, anyOf: ["find"], alsoAnyOf: fileWords),
        Rule(intent: .openFile, anyOf: ["open"], alsoAnyOf: fileWords, startsWith: ["open"]),
```
3. In `match(_:)`, replace the guard line with:
```swift
        // Claude requests and web searches are Laya's. "open/launch …" is Laya's unless it names a file word.
        let namesFile = fileWords.contains(where: has)
        if has("claude") || webLeadIns.contains(where: starts)
            || (!namesFile && appLeadIns.contains(where: starts)) { return nil }
```

- [ ] **Step 5: Temporary assistant case**

In `Sources/AssistantCore/Assistant.swift`, add as the last case of the `switch intent` in `perform(_:_:)`. Task 5 replaces it:
```swift
        case .quitApp, .hideApp, .minimizeWindow, .fullScreen, .closeWindow,
             .createFolder, .createFile, .findFile, .openFile, .revealFile:
            return Outcome("Relay can't do that yet.", .info)
```

- [ ] **Step 6: Add routing phrases**

In `Tests/RoutingTests/phrases.json`, append these entries to `phrases`. Keep `minimumAccuracy` at 1.0:
```json
    {"text": "quit slack", "expected": "quit_app"},
    {"text": "close spotify completely", "expected": "quit_app"},
    {"text": "hide this app", "expected": "hide_app"},
    {"text": "minimize this window", "expected": "minimize_window"},
    {"text": "make this full screen", "expected": "full_screen"},
    {"text": "close the tab", "expected": "close_window"},
    {"text": "make a new folder called invoices", "expected": "create_folder"},
    {"text": "create a text file called todo in documents", "expected": "create_file"},
    {"text": "open the budget spreadsheet", "expected": "open_file"},
    {"text": "find my lease agreement", "expected": "find_file"},
    {"text": "where is the tax document", "expected": "find_file"},
    {"text": "show the downloads folder in finder", "expected": "reveal_file"},
    {"text": "screenshot this window", "expected": "screenshot"},
    {"text": "copy a screenshot", "expected": "screenshot"},
    {"text": "screenshot an area", "expected": "screenshot"},
```

- [ ] **Step 7: Run all tests and the routing baseline**

Run: `make test`
Expected: everything passes, including all of A's rule tests (minus the 4 moved phrases).

Run: `make test-routing`
Expected: `routing accuracy: 49/49 = 1.0`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Routing Sources/AssistantCore Tests/RoutingTests
git commit -m "Add rules for app, window and file commands" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Workspace types and pure helpers

**Files:**
- Create: `Sources/SystemControls/WorkspaceControlling.swift`
- Create: `Sources/SystemControls/UniqueName.swift`
- Create: `Sources/SystemControls/FileSearch.swift`
- Create: `Sources/SystemControls/ScreenshotCommand.swift`
- Create: `Sources/SystemControls/WindowList.swift`
- Modify: `Sources/SystemControls/SystemControlling.swift` (3 new error cases)
- Modify: `Sources/AssistantCore/Assistant.swift` (temporary error mapping, replaced in Task 5)
- Test: `Tests/SystemControlsTests/WorkspaceHelpersTests.swift`

**Interfaces:**
- Consumes: `InstalledApp`, `ScreenshotOptions` (Extraction); `SystemControlError` (A).
- Produces:
  - `public enum WindowShortcut: Sendable, Equatable { case minimize, fullScreen, close }`
  - `public enum ScreenshotResult: Sendable, Equatable { case saved(URL), copied, cancelled }`
  - `public struct FileMatch: Sendable, Equatable, Hashable { name: String; url: URL; lastUsed: Date?; init(name:url:lastUsed:) }`
  - `public protocol WorkspaceControlling: Sendable` (spec §3 signatures)
  - `SystemControlError` cases `.appNotRunning(String)`, `.noFrontWindow`, `.searchFailed(String)`
  - `UniqueName.available(for:in:) -> URL`
  - `FileSearch.rank(paths:query:home:lastUsed:) -> [FileMatch]` and `FileSearch.pathLimit = 300`
  - `ScreenshotCommand.arguments(for:file:windowID:) -> [String]` and `ScreenshotCommand.timeout(for:) -> Duration`
  - `WindowList.frontWindowID(pid:windows:) -> Int?`

- [ ] **Step 1: Write the failing tests**

`Tests/SystemControlsTests/WorkspaceHelpersTests.swift`:
```swift
import Foundation
import Testing
@testable import Extraction
@testable import SystemControls

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func uniqueNameNumbersClashesLikeFinder() throws {
    let folder = try temporaryFolder()
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("invoices"), withIntermediateDirectories: false)
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices 2")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("invoices 2"), withIntermediateDirectories: false)
    #expect(UniqueName.available(for: "invoices", in: folder).lastPathComponent == "invoices 3")
}

@Test func uniqueNameKeepsTheExtension() throws {
    let folder = try temporaryFolder()
    FileManager.default.createFile(atPath: folder.appendingPathComponent("todo.txt").path, contents: Data())
    #expect(UniqueName.available(for: "todo.txt", in: folder).lastPathComponent == "todo 2.txt")
}

private let home = URL(fileURLWithPath: "/Users/test")

@Test func searchDropsLibraryHiddenAndAppContents() {
    let paths = ["/Users/test/Library/Caches/budget.db", "/Users/test/.config/budget", "/Users/test/Apps/Budget.app/Contents/budget",
                 "/Users/test/Documents/Budget.xlsx"]
    let ranked = FileSearch.rank(paths: paths, query: "budget", home: home) { _ in nil }
    #expect(ranked.map(\.name) == ["Budget.xlsx"])
}

@Test func searchRanksExactThenPrefixThenContainsThenRecency() {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let paths = ["/Users/test/a/my budget notes.txt", "/Users/test/b/budget 2025.xlsx",
                 "/Users/test/c/budget 2026.xlsx", "/Users/test/d/Budget.pdf"]
    let ranked = FileSearch.rank(paths: paths, query: "budget", home: home) { url in
        url.path.contains("2026") ? new : old
    }
    #expect(ranked.map(\.name) == ["Budget.pdf", "budget 2026.xlsx", "budget 2025.xlsx", "my budget notes.txt"])
}

@Test func searchKeepsAtMostEight() {
    let paths = (1...20).map { "/Users/test/Documents/tax \($0).pdf" }
    #expect(FileSearch.rank(paths: paths, query: "tax", home: home) { _ in nil }.count == 8)
}

private let shot = URL(fileURLWithPath: "/Users/test/Desktop/Screenshot.png")

@Test(arguments: [
    (ScreenshotOptions(target: .screen, toClipboard: false, openAfter: false), ["-x", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .window, toClipboard: false, openAfter: false), ["-x", "-l", "42", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .area, toClipboard: false, openAfter: false), ["-x", "-i", "-s", "/Users/test/Desktop/Screenshot.png"]),
    (ScreenshotOptions(target: .screen, toClipboard: true, openAfter: false), ["-x", "-c"]),
    (ScreenshotOptions(target: .window, toClipboard: true, openAfter: false), ["-x", "-c", "-l", "42"]),
    (ScreenshotOptions(target: .area, toClipboard: true, openAfter: false), ["-x", "-c", "-i", "-s"]),
])
func screenshotArguments(_ options: ScreenshotOptions, _ expected: [String]) {
    #expect(ScreenshotCommand.arguments(for: options, file: options.toClipboard ? nil : shot, windowID: 42) == expected)
}

@Test func areaScreenshotsGetLongerTimeout() {
    #expect(ScreenshotCommand.timeout(for: ScreenshotOptions(target: .area, toClipboard: false, openAfter: false)) == .seconds(60))
    #expect(ScreenshotCommand.timeout(for: ScreenshotOptions(target: .window, toClipboard: false, openAfter: false)) == .seconds(15))
}

@Test func frontWindowIsTheFirstNormalWindowOfTheApp() {
    let windows: [[String: Any]] = [
        ["kCGWindowOwnerPID": 7, "kCGWindowLayer": 25, "kCGWindowOwnerName": "Control Centre", "kCGWindowNumber": 1],
        ["kCGWindowOwnerPID": 9, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Relay", "kCGWindowNumber": 2],
        ["kCGWindowOwnerPID": 42, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Safari", "kCGWindowNumber": 3],
        ["kCGWindowOwnerPID": 42, "kCGWindowLayer": 0, "kCGWindowOwnerName": "Safari", "kCGWindowNumber": 4],
    ]
    #expect(WindowList.frontWindowID(pid: 42, windows: windows) == 3)
    #expect(WindowList.frontWindowID(pid: 9, windows: windows) == nil)
    #expect(WindowList.frontWindowID(pid: 5, windows: windows) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=WorkspaceHelpersTests`
Expected: the build fails with `cannot find 'UniqueName' in scope`.

- [ ] **Step 3: Implement**

`Sources/SystemControls/WorkspaceControlling.swift`:
```swift
import Extraction
import Foundation

public enum WindowShortcut: Sendable, Equatable {
    case minimize   // ⌘M
    case fullScreen // ⌃⌘F
    case close      // ⌘W
}

public enum ScreenshotResult: Sendable, Equatable {
    case saved(URL)
    case copied
    case cancelled
}

public struct FileMatch: Sendable, Equatable, Hashable {
    public let name: String
    public let url: URL
    public let lastUsed: Date?

    public init(name: String, url: URL, lastUsed: Date?) {
        self.name = name
        self.url = url
        self.lastUsed = lastUsed
    }
}

/// Apps, windows, files and screenshots. A protocol so the assistant can be tested with a fake.
public protocol WorkspaceControlling: Sendable {
    /// Regular (Dock) apps that are running, excluding Relay.
    func runningApps() async -> [InstalledApp]
    /// The app in front, or nil when Relay itself is in front.
    func frontmostAppName() async -> String?
    /// A normal Quit: apps may still ask to save.
    func quit(appNamed name: String) async throws
    func hide(appNamed name: String) async throws
    /// Sends ⌘M / ⌃⌘F / ⌘W to the app in front.
    func sendWindowShortcut(_ shortcut: WindowShortcut) async throws
    /// The folder of the front Finder window, or nil unless Finder is in front with a window.
    func frontFinderFolder() async throws -> URL?
    func createFolder(named name: String, in folder: URL) async throws -> URL
    func createFile(named name: String, in folder: URL) async throws -> URL
    /// Files in the home folder whose names match, best first, at most 8.
    func searchFiles(_ query: String) async throws -> [FileMatch]
    func open(_ url: URL) async throws
    func reveal(_ url: URL) async throws
    func captureScreenshot(_ options: ScreenshotOptions) async throws -> ScreenshotResult
}
```

In `Sources/SystemControls/SystemControlling.swift`, add to `SystemControlError` after `case failed(String)`:
```swift
    case appNotRunning(String)
    case noFrontWindow
    case searchFailed(String)
```

`Sources/SystemControls/UniqueName.swift`:
```swift
import Foundation

/// The first free name in a folder, numbered like Finder: "invoices", "invoices 2", "todo 2.txt".
public enum UniqueName {
    public static func available(for name: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
```

`Sources/SystemControls/FileSearch.swift`:
```swift
import Foundation

/// Filters and ranks `mdfind` results: exact name, then prefix, then contains; ties by most recently used.
public enum FileSearch {
    public static let limit = 8
    /// Only this many `mdfind` paths are considered, so a vague query can't stall Relay.
    public static let pathLimit = 300

    public static func rank(paths: [String], query: String, home: URL, lastUsed: (URL) -> Date?) -> [FileMatch] {
        let q = query.lowercased()
        let library = home.appendingPathComponent("Library").path + "/"
        let scored = paths.prefix(pathLimit).compactMap { path -> (match: FileMatch, tier: Int)? in
            guard !path.hasPrefix(library),
                  !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                  !path.contains(".app/")
            else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            let tier = stem == q || name.lowercased() == q ? 0
                : stem.hasPrefix(q) ? 1
                : name.lowercased().contains(q) ? 2
                : 3
            return (FileMatch(name: name, url: url, lastUsed: lastUsed(url)), tier)
        }
        let sorted = scored.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            return (a.match.lastUsed ?? .distantPast) > (b.match.lastUsed ?? .distantPast)
        }
        return sorted.prefix(limit).map(\.match)
    }
}
```

`Sources/SystemControls/ScreenshotCommand.swift`:
```swift
import Extraction
import Foundation

/// `screencapture` arguments for each screenshot variant (spec §3.3).
public enum ScreenshotCommand {
    public static func arguments(for options: ScreenshotOptions, file: URL?, windowID: Int?) -> [String] {
        var arguments = ["-x"]
        if options.toClipboard { arguments.append("-c") }
        switch options.target {
        case .screen: break
        case .window: if let windowID { arguments += ["-l", String(windowID)] }
        case .area: arguments += ["-i", "-s"]
        }
        if !options.toClipboard, let file { arguments.append(file.path) }
        return arguments
    }

    /// Area shots wait for the user to drag, so they get longer than the usual 15 s.
    public static func timeout(for options: ScreenshotOptions) -> Duration {
        options.target == .area ? .seconds(60) : .seconds(15)
    }
}
```

`Sources/SystemControls/WindowList.swift`:
```swift
/// Picks the front window of an app from `CGWindowListCopyWindowInfo` output (front-to-back order).
public enum WindowList {
    public static func frontWindowID(pid: Int32, windows: [[String: Any]]) -> Int? {
        windows.first { window in
            (window["kCGWindowOwnerPID"] as? Int).map(Int32.init) == pid
                && (window["kCGWindowLayer"] as? Int) == 0
                && (window["kCGWindowOwnerName"] as? String) != "Relay"
        }?["kCGWindowNumber"] as? Int
    }
}
```

In `Sources/AssistantCore/Assistant.swift`, in `control(_:_:)`'s `switch error`, add after the `.failed` case. Task 5 replaces it:
```swift
            case .appNotRunning, .noFrontWindow, .searchFailed:
                return Outcome("Couldn't \(action).", .problem)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=WorkspaceHelpersTests`
Expected: all helper tests pass.

Run: `make test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemControls Sources/AssistantCore Tests/SystemControlsTests
git commit -m "Add workspace protocol, unique names, file search ranking and screenshot commands" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Real workspace implementation

**Files:**
- Modify: `Sources/SystemControls/KeyEvents.swift` (generic key press plus window shortcuts)
- Create: `Sources/SystemControls/MacWorkspaceControls.swift`
- Test: `Tests/SystemControlsTests/MacWorkspaceControlsTests.swift`

**Interfaces:**
- Consumes: Task 3's protocol, types, helpers and errors; A's `Permissions`, `ProcessRunner`, `CommandRunning`, `ScreenshotLocation`.
- Produces:
  - `public final class MacWorkspaceControls: WorkspaceControlling { init(runner: any CommandRunning = ProcessRunner(), areaRunner: any CommandRunning = ProcessRunner(timeout: .seconds(60))) }`
  - `KeyEvents.shortcut(for:) -> (key: CGKeyCode, flags: CGEventFlags)`

- [ ] **Step 1: Write the failing tests**

`Tests/SystemControlsTests/MacWorkspaceControlsTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import SystemControls

@Test func windowShortcutsUseTheStandardKeys() {
    #expect(KeyEvents.shortcut(for: .minimize).key == 46)
    #expect(KeyEvents.shortcut(for: .minimize).flags == .maskCommand)
    #expect(KeyEvents.shortcut(for: .fullScreen).key == 3)
    #expect(KeyEvents.shortcut(for: .fullScreen).flags == [.maskControl, .maskCommand])
    #expect(KeyEvents.shortcut(for: .close).key == 13)
}

@Test func createsFoldersAndFilesWithoutOverwriting() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let controls = MacWorkspaceControls()

    let first = try await controls.createFolder(named: "invoices", in: folder)
    let second = try await controls.createFolder(named: "invoices", in: folder)
    #expect(first.lastPathComponent == "invoices")
    #expect(second.lastPathComponent == "invoices 2")

    let note = try await controls.createFile(named: "todo.txt", in: folder)
    try "keep me".write(to: note, atomically: true, encoding: .utf8)
    let another = try await controls.createFile(named: "todo.txt", in: folder)
    #expect(another.lastPathComponent == "todo 2.txt")
    #expect(try String(contentsOf: note, encoding: .utf8) == "keep me")
}

@Test func creatingInAMissingFolderFails() async {
    let missing = URL(fileURLWithPath: "/nonexistent-relay-folder")
    await #expect(throws: SystemControlError.self) {
        _ = try await MacWorkspaceControls().createFolder(named: "x", in: missing)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=MacWorkspaceControlsTests`
Expected: the build fails with `type 'KeyEvents' has no member 'shortcut'` / `cannot find 'MacWorkspaceControls' in scope`.

- [ ] **Step 3: Generalize key presses**

In `Sources/SystemControls/KeyEvents.swift`, replace `pressLockShortcut()` with:
```swift
    /// ⌃⌘Q, the system Lock Screen shortcut.
    @MainActor static func pressLockShortcut() {
        pressKey(12 /* kVK_ANSI_Q */, flags: [.maskControl, .maskCommand])
    }

    static func shortcut(for shortcut: WindowShortcut) -> (key: CGKeyCode, flags: CGEventFlags) {
        switch shortcut {
        case .minimize: (46 /* kVK_ANSI_M */, .maskCommand)
        case .fullScreen: (3 /* kVK_ANSI_F */, [.maskControl, .maskCommand])
        case .close: (13 /* kVK_ANSI_W */, .maskCommand)
        }
    }

    @MainActor static func press(_ shortcut: WindowShortcut) {
        let keys = self.shortcut(for: shortcut)
        pressKey(keys.key, flags: keys.flags)
    }

    /// Posts a key down and up with modifiers to the frontmost app.
    @MainActor static func pressKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
```

- [ ] **Step 4: Implement the real workspace controls**

`Sources/SystemControls/MacWorkspaceControls.swift`:
```swift
import AppKit
import Extraction
import Foundation

/// The real implementation: NSWorkspace, key events, Finder AppleScript, `mdfind` and `screencapture`.
public final class MacWorkspaceControls: WorkspaceControlling {
    private let runner: any CommandRunning
    private let areaRunner: any CommandRunning

    public init(runner: any CommandRunning = ProcessRunner(),
                areaRunner: any CommandRunning = ProcessRunner(timeout: .seconds(60))) {
        self.runner = runner
        self.areaRunner = areaRunner
    }

    // MARK: Apps and windows

    @MainActor private static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    @MainActor private static func frontmostApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app
    }

    public func runningApps() async -> [InstalledApp] {
        await MainActor.run {
            Self.regularApps().compactMap { app in
                guard let name = app.localizedName, let url = app.bundleURL else { return nil }
                return InstalledApp(name: name, url: url)
            }
        }
    }

    public func frontmostAppName() async -> String? {
        await MainActor.run { Self.frontmostApp()?.localizedName }
    }

    public func quit(appNamed name: String) async throws {
        try await MainActor.run {
            guard let app = Self.regularApps().first(where: { $0.localizedName == name }) else {
                throw SystemControlError.appNotRunning(name)
            }
            _ = app.terminate() // a normal Quit; never forceTerminate()
        }
    }

    public func hide(appNamed name: String) async throws {
        try await MainActor.run {
            guard let app = Self.regularApps().first(where: { $0.localizedName == name }) else {
                throw SystemControlError.appNotRunning(name)
            }
            _ = app.hide()
        }
    }

    public func sendWindowShortcut(_ shortcut: WindowShortcut) async throws {
        try Permissions.requireAccessibility()
        try await MainActor.run {
            guard Self.frontmostApp() != nil else { throw SystemControlError.noFrontWindow }
            KeyEvents.press(shortcut)
        }
    }

    // MARK: Files

    public func frontFinderFolder() async throws -> URL? {
        try await MainActor.run {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return nil }
            let source = "tell application \"Finder\" to if (count of Finder windows) > 0 then "
                + "POSIX path of (target of front Finder window as alias)"
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                if error[NSAppleScript.errorNumber] as? Int == -1743 { throw SystemControlError.automationDenied }
                return nil
            }
            guard let path = result?.stringValue, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    public func createFolder(named name: String, in folder: URL) async throws -> URL {
        try Self.requireFolder(folder)
        let url = UniqueName.available(for: name, in: folder)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw SystemControlError.failed(error.localizedDescription)
        }
        return url
    }

    public func createFile(named name: String, in folder: URL) async throws -> URL {
        try Self.requireFolder(folder)
        let url = UniqueName.available(for: name, in: folder)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw SystemControlError.failed("couldn't write in \(folder.lastPathComponent)")
        }
        return url
    }

    private static func requireFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SystemControlError.failed("the folder \(folder.path) doesn't exist")
        }
    }

    public func searchFiles(_ query: String) async throws -> [FileMatch] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result: CommandResult
        do {
            result = try await runner.run("/usr/bin/mdfind", ["-onlyin", home.path, "-name", query])
        } catch {
            throw SystemControlError.searchFailed(error.localizedDescription)
        }
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.searchFailed(reason.isEmpty ? "mdfind exited \(result.status)" : reason)
        }
        let paths = result.stdout.split(separator: "\n").prefix(FileSearch.pathLimit).map(String.init)
        return FileSearch.rank(paths: paths, query: query, home: home) { url in
            try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        }
    }

    public func open(_ url: URL) async throws {
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    public func reveal(_ url: URL) async throws {
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Screenshots

    public func captureScreenshot(_ options: ScreenshotOptions) async throws -> ScreenshotResult {
        try Permissions.requireScreenRecording()
        var windowID: Int?
        if options.target == .window {
            windowID = await MainActor.run { () -> Int? in
                guard let app = Self.frontmostApp() else { return nil }
                let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]] ?? []
                return WindowList.frontWindowID(pid: app.processIdentifier, windows: list)
            }
            guard windowID != nil else { throw SystemControlError.noFrontWindow }
        }
        let file: URL? = options.toClipboard ? nil : ScreenshotLocation.folder(
            defaultsValue: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser
        ).appendingPathComponent(ScreenshotLocation.fileName(for: Date()))

        let arguments = ScreenshotCommand.arguments(for: options, file: file, windowID: windowID)
        let result = try await (options.target == .area ? areaRunner : runner).run("/usr/sbin/screencapture", arguments)
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemControlError.failed(reason.isEmpty ? "screencapture exited \(result.status)" : reason)
        }
        guard let file else { return .copied }
        return FileManager.default.fileExists(atPath: file.path) ? .saved(file) : .cancelled
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=MacWorkspaceControlsTests`
Expected: 3 tests pass.

Run: `make test`
Expected: the whole suite passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/SystemControls Tests/SystemControlsTests
git commit -m "Add real workspace controls: apps, window shortcuts, files, search and screenshots" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Assistant handles apps, windows, files and screenshots

**Files:**
- Modify: `Sources/SystemControls/SystemControlling.swift` (remove `takeScreenshot()`)
- Modify: `Sources/SystemControls/MacSystemControls.swift` (remove `takeScreenshot()`)
- Modify: `Sources/AssistantCore/Assistant.swift`
- Modify: `Sources/RelayApp/AppController.swift` (pass `MacWorkspaceControls()`)
- Modify: `Tests/AssistantCoreTests/Fakes.swift` (`FakeWorkspace`; `Harness`; drop `FakeSystem.takeScreenshot`)
- Modify: `Tests/AssistantCoreTests/SystemCommandTests.swift` (screenshot cases move to the new tests)
- Test: `Tests/AssistantCoreTests/WorkspaceCommandTests.swift`

**Interfaces:**
- Consumes:
  - Task 1 parsers
  - Task 2 intents
  - Task 3/4 `WorkspaceControlling`, `FileMatch`, `ScreenshotResult`, `WindowShortcut`, new errors, `MacWorkspaceControls`
  - `AppMatcher` (existing)
- Produces:
  - `AssistantDependencies.workspace`, as the init parameter `workspace:` after `system:`
  - `public enum FileMatchAction: Sendable, Equatable { case open, reveal }`
  - `Assistant.fileMatches: [FileMatch]`, `Assistant.fileMatchAction: FileMatchAction`
  - `Assistant.pick(_ match: FileMatch) async`

- [ ] **Step 1: Update the fakes and move A's screenshot tests**

In `Tests/AssistantCoreTests/Fakes.swift`:
- delete `FakeSystem`'s `takeScreenshot()` method
- add `let workspace = FakeWorkspace()` to `Harness` after `let system = FakeSystem()`
- in `Harness.init`, pass `workspace: workspace` directly after `system: system,`
- add this fake:
```swift
actor FakeWorkspace: WorkspaceControlling {
    private(set) var calls: [String] = []
    var running = [InstalledApp(name: "Slack", url: URL(fileURLWithPath: "/Applications/Slack.app")),
                   InstalledApp(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))]
    var frontmost: String? = "Safari"
    var finderFolder: URL?
    var finderDenied = false
    var matches: [FileMatch] = []
    var screenshotResult = ScreenshotResult.saved(URL(fileURLWithPath: "/Users/test/Desktop/Screenshot.png"))
    var failure: SystemControlError?

    func setFrontmost(_ name: String?) { frontmost = name }
    func setFinderFolder(_ url: URL?) { finderFolder = url }
    func denyFinder() { finderDenied = true }
    func setMatches(_ list: [FileMatch]) { matches = list }
    func setScreenshotResult(_ result: ScreenshotResult) { screenshotResult = result }
    func fail(with error: SystemControlError?) { failure = error }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func runningApps() -> [InstalledApp] { running }
    func frontmostAppName() -> String? { frontmost }
    func quit(appNamed name: String) throws { try record("quit(\(name))") }
    func hide(appNamed name: String) throws { try record("hide(\(name))") }
    func sendWindowShortcut(_ shortcut: WindowShortcut) throws { try record("shortcut(\(shortcut))") }
    func frontFinderFolder() throws -> URL? {
        if finderDenied { throw SystemControlError.automationDenied }
        return finderFolder
    }
    func createFolder(named name: String, in folder: URL) throws -> URL {
        try record("createFolder(\(name), \(folder.lastPathComponent))")
        return folder.appendingPathComponent(name)
    }
    func createFile(named name: String, in folder: URL) throws -> URL {
        try record("createFile(\(name), \(folder.lastPathComponent))")
        return folder.appendingPathComponent(name)
    }
    func searchFiles(_ query: String) throws -> [FileMatch] { try record("search(\(query))"); return matches }
    func open(_ url: URL) throws { try record("open(\(url.lastPathComponent))") }
    func reveal(_ url: URL) throws { try record("reveal(\(url.lastPathComponent))") }
    func captureScreenshot(_ options: ScreenshotOptions) throws -> ScreenshotResult {
        try record("screenshot(\(options.target), clipboard: \(options.toClipboard))")
        return screenshotResult
    }
}
```
- add `@testable import Extraction` to the imports if it isn't already there

In `Tests/AssistantCoreTests/SystemCommandTests.swift`, make three edits, since screenshots now go through the workspace and are tested in the new file:
- remove the row `("take a screenshot", .screenshot, "takeScreenshot()", "Screenshot saved to Desktop"),` from `darkModeFocusLockMediaAndScreenshot`
- remove the `(.screenRecordingDenied, .screenshot, …)` row from `permissionProblemsSayWhatToAllow`
- remove the `let x = Harness(transcript: "take a screenshot" …` block (4 lines) from `deviceAndShortcutFailures`

- [ ] **Step 2: Write the failing tests**

`Tests/AssistantCoreTests/WorkspaceCommandTests.swift`:
```swift
import Foundation
import Testing
@testable import AssistantCore
@testable import Routing
@testable import SystemControls

private let home = FileManager.default.homeDirectoryForCurrentUser

private func match(_ name: String) -> FileMatch {
    FileMatch(name: name, url: home.appendingPathComponent("Documents/\(name)"), lastUsed: nil)
}

// MARK: Apps and windows

@MainActor @Test func quitsANamedRunningApp() async {
    let h = Harness(transcript: "quit slack", outcome: .intent(.quitApp))
    await h.speak()
    #expect(await h.workspace.calls == ["quit(Slack)"])
    #expect(h.assistant.message == "Quit Slack")
    #expect(h.assistant.resultKind == .success)
}

@MainActor @Test func appThatIsNotRunningIsExplained() async {
    let h = Harness(transcript: "close spotify completely", outcome: .intent(.quitApp))
    await h.speak()
    #expect(await h.workspace.calls.isEmpty)
    #expect(h.assistant.message?.hasPrefix("Spotify isn't running. Running: ") == true)
    #expect(h.assistant.resultKind == .problem)
}

@MainActor @Test func hidesTheAppInFront() async {
    let h = Harness(transcript: "hide this app", outcome: .intent(.hideApp))
    await h.speak()
    #expect(await h.workspace.calls == ["hide(Safari)"])
    #expect(h.assistant.message == "Hid Safari")
}

@MainActor @Test func nothingInFrontIsExplained() async {
    let h = Harness(transcript: "hide this app", outcome: .intent(.hideApp))
    await h.workspace.setFrontmost(nil)
    await h.speak()
    #expect(h.assistant.message == "There's no app window in front to hide.")
}

@MainActor @Test func windowShortcuts() async {
    let cases: [(String, RoutedIntent, String, String)] = [
        ("minimize this window", .minimizeWindow, "shortcut(minimize)", "Minimized Safari"),
        ("make this full screen", .fullScreen, "shortcut(fullScreen)", "Toggled full screen"),
        ("close the tab", .closeWindow, "shortcut(close)", "Closed window"),
    ]
    for (transcript, intent, call, message) in cases {
        let h = Harness(transcript: transcript, outcome: .intent(intent))
        await h.speak()
        #expect(await h.workspace.calls == [call], "\(transcript)")
        #expect(h.assistant.message == message, "\(transcript)")
    }
}

@MainActor @Test func windowShortcutWithNoWindowInFront() async {
    let h = Harness(transcript: "minimize this window", outcome: .intent(.minimizeWindow))
    await h.workspace.fail(with: .noFrontWindow)
    await h.speak()
    #expect(h.assistant.message == "There's no app window in front to minimize.")
}

// MARK: Creating

@MainActor @Test func newFolderGoesOnTheDesktopByDefault() async {
    let h = Harness(transcript: "make a new folder called invoices", outcome: .intent(.createFolder))
    await h.speak()
    #expect(await h.workspace.calls == ["createFolder(invoices, Desktop)"])
    #expect(h.assistant.message == "Created folder “invoices” on Desktop")
}

@MainActor @Test func newFolderGoesInTheFrontFinderWindow() async {
    let h = Harness(transcript: "make a new folder called invoices", outcome: .intent(.createFolder))
    await h.workspace.setFinderFolder(URL(fileURLWithPath: "/Users/test/Projects"))
    await h.speak()
    #expect(await h.workspace.calls == ["createFolder(invoices, Projects)"])
    #expect(h.assistant.message == "Created folder “invoices” in Projects")
}

@MainActor @Test func deniedFinderAutomationFallsBackToTheDesktopWithANote() async {
    let h = Harness(transcript: "make a new folder called invoices", outcome: .intent(.createFolder))
    await h.workspace.denyFinder()
    await h.speak()
    #expect(await h.workspace.calls == ["createFolder(invoices, Desktop)"])
    #expect(h.assistant.message
        == "Created folder “invoices” on Desktop (allow Relay to control Finder to use the open Finder window)")
}

@MainActor @Test func newFilesUseTheSpokenPlaceAndExtension() async {
    let h = Harness(transcript: "create a text file called todo in documents", outcome: .intent(.createFile))
    await h.speak()
    #expect(await h.workspace.calls == ["createFile(todo.txt, Documents)"])
    #expect(h.assistant.message == "Created “todo.txt” in Documents")

    let md = Harness(transcript: "create a file called notes dot md", outcome: .intent(.createFile))
    await md.speak()
    #expect(await md.workspace.calls == ["createFile(notes.md, Desktop)"])
}

@MainActor @Test func missingNameAsksForOne() async {
    let h = Harness(transcript: "make a new folder", outcome: .intent(.createFolder))
    await h.speak()
    #expect(h.assistant.message == "What should the folder be called?")
    #expect(h.assistant.resultKind == .info)
    #expect(await h.workspace.calls.isEmpty)
}

@MainActor @Test func createFailureIsExplained() async {
    let h = Harness(transcript: "make a new folder called invoices", outcome: .intent(.createFolder))
    await h.workspace.fail(with: .failed("disk full"))
    await h.speak()
    #expect(h.assistant.message == "Couldn't create “invoices”: disk full")
}

// MARK: Finding and opening

@MainActor @Test func oneMatchIsOpenedOrRevealed() async {
    let o = Harness(transcript: "open the budget spreadsheet", outcome: .intent(.openFile))
    await o.workspace.setMatches([match("Budget 2026.xlsx")])
    await o.speak()
    #expect(await o.workspace.calls == ["search(budget)", "open(Budget 2026.xlsx)"])
    #expect(o.assistant.message == "Opened “Budget 2026.xlsx”")

    let f = Harness(transcript: "find my lease agreement", outcome: .intent(.findFile))
    await f.workspace.setMatches([match("lease.pdf")])
    await f.speak()
    #expect(await f.workspace.calls == ["search(lease)", "reveal(lease.pdf)"])
    #expect(f.assistant.message == "Showed “lease.pdf” in Finder")
}

@MainActor @Test func severalMatchesAreListedAndClearedWhenListeningStarts() async {
    let h = Harness(transcript: "open my tax document", outcome: .intent(.openFile))
    await h.workspace.setMatches([match("tax 2024.pdf"), match("tax 2025.pdf"), match("tax notes.txt")])
    await h.speak()
    #expect(await h.workspace.calls == ["search(tax)"])
    #expect(h.assistant.fileMatches.count == 3)
    #expect(h.assistant.fileMatchAction == .open)
    #expect(h.assistant.message == "Found 3 files matching “tax”. Pick one in the panel.")
    #expect(h.assistant.resultKind == .info)

    await h.assistant.hotkeyPressed()
    #expect(h.assistant.fileMatches.isEmpty)
}

@MainActor @Test func noMatchesAndNoSearchText() async {
    let h = Harness(transcript: "open my tax document", outcome: .intent(.openFile))
    await h.speak()
    #expect(h.assistant.message == "No files matching “tax”.")

    let w = Harness(transcript: "open it", outcome: .intent(.openFile))
    await w.speak()
    #expect(w.assistant.message == "Which file?")
}

@MainActor @Test func revealingANamedPlaceOpensThatFolder() async {
    let h = Harness(transcript: "show the downloads folder in finder", outcome: .intent(.revealFile))
    await h.speak()
    #expect(await h.workspace.calls == ["reveal(Downloads)"])
    #expect(h.assistant.message == "Showed Downloads in Finder")
}

@MainActor @Test func searchFailureIsExplained() async {
    let h = Harness(transcript: "find my lease agreement", outcome: .intent(.findFile))
    await h.workspace.fail(with: .searchFailed("Spotlight is off"))
    await h.speak()
    #expect(h.assistant.message == "Couldn't search your files: Spotlight is off")
}

@MainActor @Test func pickingAFileThatVanishedKeepsTheList() async {
    let h = Harness(transcript: "open my tax document", outcome: .intent(.openFile))
    let gone = FileMatch(name: "gone.pdf", url: URL(fileURLWithPath: "/nonexistent/gone.pdf"), lastUsed: nil)
    await h.workspace.setMatches([gone, match("tax 2025.pdf")])
    await h.speak()
    await h.assistant.pick(gone)
    #expect(h.assistant.message == "That file is no longer there.")
    #expect(h.assistant.fileMatches.count == 2)
}

@MainActor @Test func pickingAFileOpensItAndClearsTheList() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: file.path, contents: Data())
    let real = FileMatch(name: file.lastPathComponent, url: file, lastUsed: nil)
    let h = Harness(transcript: "open my tax document", outcome: .intent(.openFile))
    await h.workspace.setMatches([real, match("tax 2025.pdf")])
    await h.speak()
    await h.assistant.pick(real)
    #expect(await h.workspace.calls.last == "open(\(file.lastPathComponent))")
    #expect(h.assistant.message == "Opened “\(file.lastPathComponent)”")
    #expect(h.assistant.fileMatches.isEmpty)
}

// MARK: Screenshots

@MainActor @Test func screenshotVariants() async {
    let w = Harness(transcript: "screenshot this window", outcome: .intent(.screenshot))
    await w.speak()
    #expect(await w.workspace.calls == ["screenshot(window, clipboard: false)"])
    #expect(w.assistant.message == "Window screenshot saved to Desktop")

    let c = Harness(transcript: "copy a screenshot", outcome: .intent(.screenshot))
    await c.workspace.setScreenshotResult(.copied)
    await c.speak()
    #expect(c.assistant.message == "Screenshot copied to clipboard")

    let a = Harness(transcript: "screenshot an area", outcome: .intent(.screenshot))
    await a.workspace.setScreenshotResult(.cancelled)
    await a.speak()
    #expect(a.assistant.message == "Screenshot cancelled")
    #expect(a.assistant.resultKind == .info)

    let s = Harness(transcript: "take a screenshot and show it", outcome: .intent(.screenshot))
    await s.speak()
    #expect(await s.workspace.calls == ["screenshot(screen, clipboard: false)", "open(Screenshot.png)"])
    #expect(s.assistant.message == "Screenshot saved to Desktop")
}

@MainActor @Test func screenshotProblems() async {
    let p = Harness(transcript: "take a screenshot", outcome: .intent(.screenshot))
    await p.workspace.fail(with: .screenRecordingDenied)
    await p.speak()
    #expect(p.assistant.message
        == "Relay needs Screen Recording permission to take screenshots. Allow it, then quit and reopen Relay.")
    #expect(p.assistant.missingPermission == .screenRecording)

    let f = Harness(transcript: "take a screenshot", outcome: .intent(.screenshot))
    await f.workspace.fail(with: .failed("disk full"))
    await f.speak()
    #expect(f.assistant.message == "Couldn't take a screenshot: disk full")

    let n = Harness(transcript: "screenshot this window", outcome: .intent(.screenshot))
    await n.workspace.fail(with: .noFrontWindow)
    await n.speak()
    #expect(n.assistant.message == "There's no app window in front to take a screenshot.")
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test FILTER=AssistantCoreTests`
Expected: the build fails with `extra argument 'workspace' in call` / `value of type 'Assistant' has no member 'fileMatches'`.

- [ ] **Step 4: Remove the old screenshot entry point**

- In `Sources/SystemControls/SystemControlling.swift`, delete the two lines:
  ```swift
      /// Returns where the screenshot was saved.
      func takeScreenshot() async throws -> URL
  ```
- In `Sources/SystemControls/MacSystemControls.swift`, delete the whole `public func takeScreenshot() async throws -> URL { … }` method. `ScreenshotLocation` and `Permissions` are still used by `MacWorkspaceControls`.

- [ ] **Step 5: Implement in the assistant**

In `Sources/AssistantCore/Assistant.swift`:

1. Add, next to `ResultKind`:
```swift
public enum FileMatchAction: Sendable, Equatable {
    case open
    case reveal
}
```
2. In `AssistantDependencies`, add `public var workspace: any WorkspaceControlling` after `system`. Add the init parameter `workspace: any WorkspaceControlling` right after `system: any SystemControlling,`, and assign it.
3. Add state next to `missingShortcut`:
```swift
    /// Files matching a find/open/reveal request when there was more than one; the panel lists them.
    public private(set) var fileMatches: [FileMatch] = []
    public private(set) var fileMatchAction: FileMatchAction = .open
```
4. In `hotkeyPressed()`'s `.idle` branch, next to `missingShortcut = nil`, add `fileMatches = []`.
5. Replace the whole `case .screenshot:` block in `perform` with:
```swift
        case .screenshot:
            let options = ScreenshotOptionsParser.parse(text)
            let kind = switch options.target {
            case .screen: "Screenshot"
            case .window: "Window screenshot"
            case .area: "Area screenshot"
            }
            return await control("take a screenshot") {
                switch try await self.deps.workspace.captureScreenshot(options) {
                case .saved(let file):
                    if options.openAfter { try await self.deps.workspace.open(file) }
                    return Outcome("\(kind) saved to \(file.deletingLastPathComponent().lastPathComponent)", .success)
                case .copied:
                    return Outcome("\(kind) copied to clipboard", .success)
                case .cancelled:
                    return Outcome("Screenshot cancelled", .info)
                }
            }
```
6. Replace the temporary `case .quitApp, .hideApp, … return Outcome("Relay can't do that yet.", .info)` from Task 2 with:
```swift
        case .quitApp, .hideApp:
            let quitting = intent == .quitApp
            return await control(quitting ? "quit" : "hide") {
                let name = try await self.resolveApp(AppTargetParser.parse(text))
                if quitting {
                    try await self.deps.workspace.quit(appNamed: name)
                } else {
                    try await self.deps.workspace.hide(appNamed: name)
                }
                return Outcome(quitting ? "Quit \(name)" : "Hid \(name)", .success, extracted: name)
            }

        case .minimizeWindow, .fullScreen, .closeWindow:
            let shortcut: WindowShortcut = intent == .minimizeWindow ? .minimize : intent == .fullScreen ? .fullScreen : .close
            let verb = intent == .minimizeWindow ? "minimize" : intent == .fullScreen ? "make full screen" : "close"
            return await control(verb) {
                let app = await self.deps.workspace.frontmostAppName() ?? "the window"
                try await self.deps.workspace.sendWindowShortcut(shortcut)
                let message = switch shortcut {
                case .minimize: "Minimized \(app)"
                case .fullScreen: "Toggled full screen"
                case .close: "Closed window"
                }
                return Outcome(message, .success)
            }

        case .createFolder, .createFile:
            let isFolder = intent == .createFolder
            let request = FileRequestParser.parse(text)
            guard let name = request.name else {
                return Outcome(isFolder ? "What should the folder be called?" : "What should the file be called?", .info)
            }
            return await control("create “\(name)”") {
                let (folder, note) = await self.creationFolder(for: request.location)
                let place = Self.placeDescription(folder)
                if isFolder {
                    let url = try await self.deps.workspace.createFolder(named: name, in: folder)
                    return Outcome("Created folder “\(url.lastPathComponent)” \(place)\(note)", .success, extracted: url.path)
                }
                let fileName = "\(name).\(request.fileExtension ?? "txt")"
                let url = try await self.deps.workspace.createFile(named: fileName, in: folder)
                return Outcome("Created “\(url.lastPathComponent)” \(place)\(note)", .success, extracted: url.path)
            }

        case .openFile, .findFile, .revealFile:
            guard let query = FileRequestParser.query(text) else { return Outcome("Which file?", .info) }
            if intent == .revealFile, let place = FileLocation(rawValue: query) {
                return await control("show \(Self.folderName(place))") {
                    try await self.deps.workspace.reveal(Self.url(for: place))
                    return Outcome("Showed \(Self.folderName(place)) in Finder", .success)
                }
            }
            let action: FileMatchAction = intent == .openFile ? .open : .reveal
            return await control("search your files") {
                let matches = try await self.deps.workspace.searchFiles(query)
                switch matches.count {
                case 0:
                    return Outcome("No files matching “\(query)”.", .info, extracted: query)
                case 1:
                    return try await self.act(on: matches[0], action)
                default:
                    self.fileMatches = matches
                    self.fileMatchAction = action
                    return Outcome("Found \(matches.count) files matching “\(query)”. Pick one in the panel.",
                                   .info, extracted: query)
                }
            }
```
7. In `control(_:_:)`, replace the temporary `case .appNotRunning, .noFrontWindow, .searchFailed:` line from Task 3 with:
```swift
            case .appNotRunning(let name):
                return Outcome("\(name) isn't running.", .problem)
            case .noFrontWindow:
                return Outcome("There's no app window in front to \(action).", .problem)
            case .searchFailed(let reason):
                return Outcome("Couldn't search your files: \(reason)", .problem)
```
   and add a catch **before** the final generic `catch`:
```swift
        } catch let error as NoMatchingApp {
            let running = error.running.isEmpty ? "" : " Running: \(error.running.joined(separator: ", "))."
            return Outcome("\(error.name) isn't running.\(running)", .problem)
```
8. Add these members to `Assistant`, next to the other private helpers:
```swift
    /// Opens or reveals one file the user picked from the panel list.
    public func pick(_ match: FileMatch) async {
        guard FileManager.default.fileExists(atPath: match.url.path) else {
            message = "That file is no longer there."
            resultKind = .problem
            return
        }
        let action = fileMatchAction
        let result = await control(action == .open ? "open “\(match.name)”" : "show “\(match.name)”") {
            try await self.act(on: match, action)
        }
        message = result.message
        resultKind = result.kind
        if result.kind == .success { fileMatches = [] }
    }

    private func act(on match: FileMatch, _ action: FileMatchAction) async throws -> Outcome {
        switch action {
        case .open:
            try await deps.workspace.open(match.url)
            return Outcome("Opened “\(match.name)”", .success, extracted: match.url.path)
        case .reveal:
            try await deps.workspace.reveal(match.url)
            return Outcome("Showed “\(match.name)” in Finder", .success, extracted: match.url.path)
        }
    }

    private struct NoMatchingApp: Error {
        let name: String
        let running: [String]
    }

    private func resolveApp(_ target: AppTarget) async throws -> String {
        switch target {
        case .frontmost:
            guard let name = await deps.workspace.frontmostAppName() else { throw SystemControlError.noFrontWindow }
            return name
        case .named(let spoken):
            switch AppMatcher(apps: await deps.workspace.runningApps()).match(spoken) {
            case .found(let app):
                return app.name
            case .notFound(let query, let suggestions):
                throw NoMatchingApp(name: (query.isEmpty ? spoken : query).capitalized, running: suggestions)
            }
        }
    }

    static let finderNote = " (allow Relay to control Finder to use the open Finder window)"

    /// Where to create: a spoken place, else the front Finder window's folder, else the Desktop.
    private func creationFolder(for location: FileLocation?) async -> (URL, String) {
        if let location { return (Self.url(for: location), "") }
        do {
            if let finder = try await deps.workspace.frontFinderFolder() { return (finder, "") }
        } catch SystemControlError.automationDenied {
            return (Self.url(for: .desktop), Self.finderNote)
        } catch {}
        return (Self.url(for: .desktop), "")
    }

    static func url(for location: FileLocation) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return location == .home ? home : home.appendingPathComponent(folderName(location))
    }

    static func folderName(_ location: FileLocation) -> String {
        switch location {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .home: "Home"
        }
    }

    static func placeDescription(_ folder: URL) -> String {
        folder == url(for: .desktop) ? "on Desktop" : "in \(folder.lastPathComponent)"
    }
```

In `Sources/RelayApp/AppController.swift`, pass `workspace: MacWorkspaceControls(),` directly after `system: MacSystemControls(),`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test FILTER=AssistantCoreTests`
Expected: all AssistantCore tests pass: A's (with the screenshot rows removed) and the new `WorkspaceCommandTests`.

Run: `make test`
Expected: the whole suite passes.

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests/AssistantCoreTests
git commit -m "Handle app, window, file and screenshot commands in the assistant" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: File list in the panel, checklist and bundle

**Files:**
- Modify: `Sources/RelayApp/PanelView.swift` (Pick a file section)
- Modify: `Sources/RelayApp/AppController.swift` (open the panel when matches arrive)
- Modify: `docs/manual-checklist.md`
- Modify: `docs/superpowers/specs/2026-09-28-relay-apps-windows-files-design.md` (one message wording, see Step 4)

**Interfaces:**
- Consumes: `Assistant.fileMatches`, `Assistant.pick(_:)` (Task 5); `FileMatch` (Task 3).
- Produces: UI only.

This task is UI glue, verified by the build and the manual checklist.

- [ ] **Step 1: The file list**

In `Sources/RelayApp/PanelView.swift`, add `import SystemControls` to the imports. Directly after the `if let shortcut = assistant.missingShortcut { … }` block, add:
```swift
            if !assistant.fileMatches.isEmpty {
                FileMatchesView(matches: assistant.fileMatches) { match in
                    Task { await assistant.pick(match) }
                }
            }
```
and at the end of the file:
```swift
/// The "Pick a file" list shown when a find/open/reveal request matched several files.
struct FileMatchesView: View {
    let matches: [FileMatch]
    let pick: (FileMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick a file").font(.headline)
            ForEach(matches, id: \.self) { match in
                Button { pick(match) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(match.name)
                        Text(Self.shortPath(match.url.deletingLastPathComponent()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// "/Users/me/Documents/Taxes" → "~/Documents/Taxes".
    static func shortPath(_ folder: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = folder.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
```

- [ ] **Step 2: Open the panel when matches arrive**

In `Sources/RelayApp/AppController.swift`'s `watchForPanelWorthyChanges()`:
- add `_ = assistant.fileMatches` inside the tracking closure
- add `|| !self.assistant.fileMatches.isEmpty` to the condition that shows the panel

- [ ] **Step 3: Manual checklist**

In `docs/manual-checklist.md`, add before the `decisions.jsonl` line:
```markdown
- [ ] With TextEdit open and unsaved: "quit TextEdit" shows TextEdit's save prompt (nothing is lost)
- [ ] "Hide this app" hides the app in front; "quit Slack" when Slack isn't running says so and lists running apps
- [ ] "Minimize this window" / "make this full screen" / "close the tab" act on the app in front (Safari tab closes)
- [ ] "Make a new folder called invoices": appears on the Desktop; saying it again creates "invoices 2"
- [ ] With a Finder window in front: "make a new folder called drafts" asks for Finder control once, then creates it in that window's folder
- [ ] "Create a text file called todo in documents" creates ~/Documents/todo.txt
- [ ] "Open the <name of a file you have>" with one match opens it; with several, the panel lists them and clicking one opens it
- [ ] "Find my <file>" reveals it in Finder; "show the downloads folder in finder" opens Downloads
- [ ] "Screenshot this window" captures only the front window (no pill in the image)
- [ ] "Screenshot an area": drag a region → saved; try again and press Esc → "Screenshot cancelled"
- [ ] "Copy a screenshot", then paste into Notes: the image appears
- [ ] "Take a screenshot and show it" opens the new screenshot in Preview
```

- [ ] **Step 4: Record the screenshot wording in the spec**

In `docs/superpowers/specs/2026-09-28-relay-apps-windows-files-design.md` §4, change `"There's no app window in front to <minimize / make full screen / close / quit / hide / capture>."` to `"There's no app window in front to <minimize / make full screen / close / quit / hide / take a screenshot>."`. The assistant builds this message from the action name, and the screenshot action is named "take a screenshot" (as in A's "Couldn't take a screenshot: …").

- [ ] **Step 5: Build, test and bundle**

Run: `make test`
Expected: the whole suite passes.

Run: `make test-routing`
Expected: `routing accuracy: 49/49 = 1.0`.

Run: `make app`
Expected: it ends with `Built build/Relay.app`.

- [ ] **Step 6: Commit**

```bash
git add Sources/RelayApp docs/manual-checklist.md docs/superpowers/specs/2026-09-28-relay-apps-windows-files-design.md
git commit -m "Show matching files in the panel and extend the manual checklist" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
