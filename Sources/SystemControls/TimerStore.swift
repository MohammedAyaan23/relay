import Foundation

/// Running timers, saved as JSON so they survive Relay restarting. A missing or corrupt file means none.
public struct TimerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relay/timers.json")
    }

    public func all() -> [RelayTimer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RelayTimer].self, from: data)) ?? []
    }

    /// Timers that haven't ended, soonest first.
    public func active(now: Date) -> [RelayTimer] {
        all().filter { $0.endsAt > now }.sorted { $0.endsAt < $1.endsAt }
    }

    public func start(name: String?, seconds: Int, now: Date) throws -> RelayTimer {
        var timers = active(now: now)
        let timer = RelayTimer(id: UUID(), name: name.map { Self.uniqueName($0, among: timers) },
                               endsAt: now.addingTimeInterval(TimeInterval(seconds)))
        timers.append(timer)
        try save(timers)
        return timer
    }

    public func remove(id: UUID) throws {
        try save(all().filter { $0.id != id })
    }

    public func prune(now: Date) throws {
        try save(active(now: now))
    }

    /// "pasta" → "pasta 2" → "pasta 3" while earlier ones are still running.
    static func uniqueName(_ name: String, among timers: [RelayTimer]) -> String {
        let taken = Set(timers.compactMap(\.name))
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    private func save(_ timers: [RelayTimer]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(timers).write(to: fileURL, options: .atomic)
    }
}
