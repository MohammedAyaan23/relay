import Foundation
import Testing
@testable import Routing

private struct PhraseSet: Decodable {
    struct Phrase: Decodable {
        let text: String
        let expected: String
    }
    let minimumAccuracy: Double
    let phrases: [Phrase]
}

/// Runs the real Laya model (downloads ~640 MB on first use). Run with `make test-routing`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RELAY_ROUTING_TESTS"] == "1"))
func routingAccuracyStaysAtOrAboveBaseline() async throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("phrases.json")
    let set = try JSONDecoder().decode(PhraseSet.self, from: Data(contentsOf: url))
    let router = LayaRouter()
    try await router.prepare(progress: { print($0) })

    var correct = 0
    for phrase in set.phrases {
        let decision = try await router.route(phrase.text)
        let ok = decision.outcome.logName == phrase.expected
        if ok { correct += 1 }
        let top = decision.choiceProbabilities.sorted { $0.value > $1.value }.prefix(2)
            .map { "\($0.key.rawValue) \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
        print("\(ok ? "✓" : "✗") \(phrase.text) -> \(decision.outcome.logName) "
            + "(gate \(String(format: "%.2f", decision.gateProbability)); \(top))")
    }
    let accuracy = Double(correct) / Double(set.phrases.count)
    print("routing accuracy: \(correct)/\(set.phrases.count) = \(accuracy)")
    #expect(accuracy >= set.minimumAccuracy)
}
