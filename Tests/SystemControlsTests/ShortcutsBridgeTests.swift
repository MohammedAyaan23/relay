import Foundation
import Testing
@testable import SystemControls

/// Records every call; `shortcuts list` prints `installed`; `shortcuts run` returns `runResult`.
actor FakeRunner: CommandRunning {
    var installed: [String]
    var runResult = CommandResult(status: 0, stdout: "", stderr: "")
    var runError: (any Error)?
    private(set) var calls: [[String]] = []
    private(set) var inputContents: [String] = []

    init(installed: [String]) { self.installed = installed }
    func setInstalled(_ names: [String]) { installed = names }
    func setRunResult(_ result: CommandResult) { runResult = result }
    func setRunError(_ error: (any Error)?) { runError = error }

    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        calls.append([executable] + arguments)
        if arguments.first == "list" {
            return CommandResult(status: 0, stdout: installed.joined(separator: "\n") + "\n", stderr: "")
        }
        if let i = arguments.firstIndex(of: "-i") {
            inputContents.append(try String(contentsOfFile: arguments[i + 1], encoding: .utf8))
        }
        if let runError { throw runError }
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

@Test func stalledShortcutReportsATimeout() async throws {
    let runner = FakeRunner(installed: ["Relay Brightness"])
    await runner.setRunError(CommandTimeoutError())
    await #expect(throws: SystemControlError.shortcutFailed("Relay Brightness", reason: "timed out")) {
        try await ShortcutsBridge(runner: runner).run(ShortcutsBridge.brightness, input: "0.50")
    }
}
