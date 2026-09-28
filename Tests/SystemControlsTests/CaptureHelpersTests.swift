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
    let title = "<div><h1>Relay</h1></div><div><i>Voice notes from Relay</i></div>"
    #expect(NoteBody.prepend(entry: "car needs servicing", at: date, to: nil)
        == title + "<div>Sep 28, 17:05 — car needs servicing</div>")
    #expect(NoteBody.prepend(entry: "buy milk", at: date, to: title + "<div>Sep 27, 09:00 — old</div>")
        == title + "<div>Sep 28, 17:05 — buy milk</div><div>Sep 27, 09:00 — old</div>")
    #expect(NoteBody.prepend(entry: "say \"hi\" & <b>quit</b>", at: date, to: nil)
        .hasSuffix("say \"hi\" &amp; &lt;b&gt;quit&lt;/b&gt;</div>"))
}

@Test func noteScriptPassesTextOnlyAsAnArgument() throws {
    let body = "<div>tell application \"Finder\" to quit</div>"
    let arguments = NoteScript.writeArguments(body: body, noteID: nil)
    #expect(Array(arguments.suffix(2)) == [body, ""])
    #expect(!arguments.dropLast(2).contains(where: { $0.contains("Finder") }))
    #expect(NoteScript.writeArguments(body: body, noteID: "x-coredata://1").last == "x-coredata://1")
    #expect(NoteScript.readArguments().first == "-e")
}

@Test func onlyRelaysOwnNoteIsEverChosen() throws {
    let mine = "<div><h1>Relay</h1></div><div><i>Voice notes from Relay</i></div><div>Sep 27 — old</div>"
    let users = "<div><h1>Relay</h1></div><div>Project ideas for my app called Relay</div>"
    let output = "id-user\u{1f}0\u{1f}\(users)\u{1e}id-mine\u{1f}0\u{1f}\(mine)\u{1e}"
    let candidates = NoteScript.candidates(from: output)
    #expect(candidates.count == 2)
    #expect(try NoteScript.relayNote(in: candidates)?.id == "id-mine")
    #expect(try NoteScript.relayNote(in: [NoteCandidate(id: "u", attachments: 0, body: users)]) == nil)
    #expect(throws: SystemControlError.self) {
        _ = try NoteScript.relayNote(in: [NoteCandidate(id: "m", attachments: 2, body: mine)])
    }
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

@MainActor @Test func dictatedTextIsMarkedTransientForClipboardManagers() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("relay-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    _ = PasteboardSwap.write("secret-ish", to: pasteboard)
    #expect(pasteboard.types?.contains(PasteboardSwap.transientType) == true)
}

@Test func clipboardIsRestoredOnlyAfterSlowAppsHaveHadTimeToPaste() {
    #expect(MacCaptureControls.restoreDelay >= .milliseconds(800))
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
