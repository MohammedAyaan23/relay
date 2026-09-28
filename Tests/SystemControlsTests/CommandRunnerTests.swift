import Foundation
import Testing
@testable import SystemControls

@Test func fastCommandsReturnTheirOutput() async throws {
    let result = try await ProcessRunner().run("/bin/echo", ["hi"])
    #expect(result.status == 0)
    #expect(result.stdout == "hi\n")
}

@Test func hungCommandsTimeOut() async {
    let start = Date()
    await #expect(throws: CommandTimeoutError.self) {
        _ = try await ProcessRunner(timeout: .milliseconds(500)).run("/bin/sleep", ["5"])
    }
    #expect(Date().timeIntervalSince(start) < 3)
}
