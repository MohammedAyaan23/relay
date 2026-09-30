import Foundation
import Testing
@testable import AssistantCore

@Test func appendsOneJSONLinePerEntry() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)/decisions.jsonl")
    let log = DecisionLog(fileURL: url)
    let entry = DecisionLogEntry(
        timestamp: Date(timeIntervalSince1970: 0), transcript: "open safari", gateProbability: 0.93,
        choiceProbabilities: ["open_app": 0.9], outcome: "open_app", extracted: "Safari",
        stateWasTruncated: false, result: "Opened Safari.")
    log.append(entry)
    log.append(entry)
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(DecisionLogEntry.self, from: Data(lines[0].utf8)) == entry)
}

private func entry(_ n: Int) -> DecisionLogEntry {
    DecisionLogEntry(timestamp: Date(timeIntervalSince1970: 0), transcript: "open safari \(n)", gateProbability: 0.9,
                     choiceProbabilities: ["open_app": 0.9], outcome: "open_app", extracted: "Safari",
                     stateWasTruncated: false, result: "Opened Safari.")
}

private func tempLogURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)/decisions.jsonl")
}

@Test func logIsReadableOnlyByTheUser() throws {
    let url = tempLogURL()
    DecisionLog(fileURL: url).append(entry(1))
    let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}

@Test func logKeepsOnlyTheNewestEntries() throws {
    let url = tempLogURL()
    let log = DecisionLog(fileURL: url)
    for n in 1...(DecisionLog.maxEntries + 50) { log.append(entry(n)) }
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count <= DecisionLog.maxEntries)
    #expect(lines.last?.contains("open safari \(DecisionLog.maxEntries + 50)") == true)
}

@Test func clearRemovesTheHistory() {
    let url = tempLogURL()
    let log = DecisionLog(fileURL: url)
    log.append(entry(1))
    log.clear()
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
