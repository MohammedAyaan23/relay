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
