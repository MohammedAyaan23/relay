/// Pulls the prompt for Claude Code out of a spoken command, keeping the user's wording.
public enum ClaudePromptExtractor {
    static let leadIns = [
        "ask claude code to", "ask claude to", "ask claude code", "ask claude",
        "tell claude code to", "tell claude to", "tell claude code", "tell claude",
        "have claude code", "have claude", "get claude to", "hey claude", "claude code", "claude",
    ]

    /// The prompt, or nil if nothing is left after removing the lead-in.
    public static func prompt(from transcript: String) -> String? {
        let prompt = LeadIn.strip(transcript, phrases: leadIns)
        return prompt.isEmpty ? nil : prompt
    }
}
