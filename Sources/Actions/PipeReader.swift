import Foundation

/// Reads a pipe through a readability handler, so no thread sits blocked in `read`, and can be told to stop
/// early. A child process that inherited Claude's output pipe could otherwise keep a blocking reader
/// waiting long after Claude itself had exited. Lines are split on "\n" only, never on other Unicode
/// separators, so JSON text containing U+2028 isn't cut in two.
final class PipeReader: @unchecked Sendable { // mutable state is guarded by `lock`
    let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let handle: FileHandle
    private let lock = NSLock()
    private var pending = Data()
    private var everything = Data()
    private var finished = false

    init(_ handle: FileHandle) {
        (lines, continuation) = AsyncStream<String>.makeStream()
        self.handle = handle
        handle.readabilityHandler = { [weak self] readable in
            let data = readable.availableData
            if data.isEmpty { self?.finish() } else { self?.receive(data) }
        }
    }

    /// Everything read so far, as text (used for stderr).
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: everything, as: UTF8.self)
    }

    /// Stops reading, at the end of output or when giving up, and delivers any unfinished last line.
    func finish() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let tail = pending
        pending.removeAll()
        lock.unlock()

        handle.readabilityHandler = nil
        if !tail.isEmpty { continuation.yield(String(decoding: tail, as: UTF8.self)) }
        continuation.finish()
    }

    private func receive(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        everything.append(data)
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            continuation.yield(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
    }
}
