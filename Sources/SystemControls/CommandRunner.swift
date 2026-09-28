import Foundation
import os

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

/// A command that ran longer than its runner's timeout and was terminated.
public struct CommandTimeoutError: Error, LocalizedError, Equatable {
    public init() {}
    public var errorDescription: String? { "timed out" }
}

public struct ProcessRunner: CommandRunning {
    /// Commands still running after this long are terminated, so a stuck tool can't freeze Relay.
    public let timeout: Duration

    public init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
    }

    public func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        let timeout = timeout
        return try await withCheckedThrowingContinuation { continuation in
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
                let timedOut = OSAllocatedUnfairLock(initialState: false)
                nonisolated(unsafe) let running = process
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    guard running.isRunning else { return }
                    timedOut.withLock { $0 = true }
                    running.terminate()
                }
                // Drain stderr on another queue so neither pipe can fill up and block the tool.
                let errorData = OSAllocatedUnfairLock(initialState: Data())
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    errorData.withLock { $0 = data }
                    group.leave()
                }
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                if timedOut.withLock({ $0 }) {
                    continuation.resume(throwing: CommandTimeoutError())
                    return
                }
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outputData, as: UTF8.self),
                    stderr: String(decoding: errorData.withLock { $0 }, as: UTF8.self)))
            }
        }
    }
}
