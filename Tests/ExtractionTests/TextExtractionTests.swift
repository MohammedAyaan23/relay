import Testing
@testable import Extraction

@Test func normalizeLowercasesAndTurnsPunctuationIntoSingleSpaces() {
    #expect(TextNormalizer.normalize("  Open Safari. ") == "open safari")
    #expect(TextNormalizer.normalize("Visual-Studio   Code!") == "visual studio code")
}

@Test func leadInRemovesLongestPhraseAsWholeWords() {
    #expect(LeadIn.strip("Search the web for rust", phrases: ["search", "search the web for"]) == "rust")
    #expect(LeadIn.strip("googlemaps pricing", phrases: ["google"]) == "googlemaps pricing")
}

@Test func leadInRemovesCourtesyWordsFirst() {
    #expect(LeadIn.strip("Can you please google cats?", phrases: ["google"]) == "cats")
}

@Test func searchQueryKeepsSymbolsAndCasing() {
    #expect(SearchQueryExtractor.query(from: "Search the web for rust async tutorials.") == "rust async tutorials")
    #expect(SearchQueryExtractor.query(from: "please google c++ tutorials") == "c++ tutorials")
    #expect(SearchQueryExtractor.query(from: "Can you look up the weather in Hyderabad?") == "the weather in Hyderabad")
}

@Test func searchQueryIsNilWhenNothingIsLeft() {
    #expect(SearchQueryExtractor.query(from: "search") == nil)
    #expect(SearchQueryExtractor.query(from: "Search for.") == nil)
}

@Test func claudePromptStripsLeadIns() {
    #expect(ClaudePromptExtractor.prompt(from: "Ask Claude to explain what a mutex is in one sentence.")
        == "explain what a mutex is in one sentence")
    #expect(ClaudePromptExtractor.prompt(from: "Tell Claude: run the tests") == "run the tests")
    #expect(ClaudePromptExtractor.prompt(from: "have claude write a readme for this repo") == "write a readme for this repo")
    #expect(ClaudePromptExtractor.prompt(from: "Claude, add tests for the parser") == "add tests for the parser")
    #expect(ClaudePromptExtractor.prompt(from: "fix the build") == "fix the build")
}

@Test func claudePromptIsNilWhenOnlyTheLeadInWasSaid() {
    #expect(ClaudePromptExtractor.prompt(from: "tell claude") == nil)
}

@Test func claudePromptKeepsLongDictationIntact() {
    let body = Array(repeating: "refactor the parser module", count: 60).joined(separator: " and ")
    #expect(ClaudePromptExtractor.prompt(from: "ask claude to " + body) == body)
}

@Test func meaningfulTrailingSymbolsSurvive() {
    #expect(SearchQueryExtractor.query(from: "google C#") == "C#")
    #expect(SearchQueryExtractor.query(from: "search for 50%") == "50%")
    #expect(ClaudePromptExtractor.prompt(from: "ask claude to explain the regex (briefly)") == "explain the regex (briefly)")
}
