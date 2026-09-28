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

// MARK: Final-review findings

@MainActor @Test func openingANamedPlaceOpensThatFolder() async {
    let o = Harness(transcript: "open the downloads folder", outcome: .intent(.openFile))
    await o.speak()
    #expect(await o.workspace.calls == ["open(Downloads)"])
    #expect(o.assistant.message == "Opened Downloads")

    let f = Harness(transcript: "find my documents folder", outcome: .intent(.findFile))
    await f.speak()
    #expect(await f.workspace.calls == ["reveal(Documents)"])
    #expect(f.assistant.message == "Showed Documents in Finder")
}

@MainActor @Test func windowCommandsForAnAppThatIsNotInFront() async {
    let h = Harness(transcript: "close the safari window", outcome: .intent(.closeWindow))
    await h.workspace.setFrontmost("Terminal")
    await h.speak()
    #expect(await h.workspace.calls.isEmpty)
    #expect(h.assistant.message == "Safari isn't in front.")
    #expect(h.assistant.resultKind == .problem)

    let m = Harness(transcript: "minimise safari", outcome: .intent(.minimizeWindow))
    await m.speak()
    #expect(await m.workspace.calls == ["shortcut(minimize)"])
    #expect(m.assistant.message == "Minimized Safari")
}
