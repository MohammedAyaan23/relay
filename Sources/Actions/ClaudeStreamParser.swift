import Foundation

/// Turns one line of `claude -p --output-format stream-json --verbose` output into events.
public enum ClaudeStreamParser {
    public static func parse(line: String) -> [ClaudeEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return [.ignored(type: "invalid-json")] }

        switch type {
        case "system":
            let subtype = object["subtype"] as? String ?? ""
            if subtype == "init", let id = object["session_id"] as? String {
                return [.sessionStarted(sessionID: id)]
            }
            return [.ignored(type: "system/\(subtype)")]

        case "assistant":
            return contentBlocks(of: object).compactMap { block -> ClaudeEvent? in
                switch block["type"] as? String {
                case "text":
                    guard let text = block["text"] as? String else { return nil }
                    return .text(text)
                case "tool_use":
                    let input = block["input"] as? [String: Any] ?? [:]
                    return .toolUse(name: block["name"] as? String ?? "tool", summary: summary(of: input))
                default:
                    return nil // thinking blocks
                }
            }

        case "user":
            return contentBlocks(of: object).compactMap { block -> ClaudeEvent? in
                guard block["type"] as? String == "tool_result" else { return nil }
                return .toolResult(isError: block["is_error"] as? Bool ?? false)
            }

        case "result":
            let denials = (object["permission_denials"] as? [[String: Any]] ?? []).map { denial -> String in
                let name = denial["tool_name"] as? String ?? "tool"
                let detail = summary(of: denial["tool_input"] as? [String: Any] ?? [:])
                return detail.isEmpty ? name : "\(name): \(detail)"
            }
            return [.finished(ClaudeResult(
                text: object["result"] as? String,
                sessionID: object["session_id"] as? String ?? "",
                durationMs: object["duration_ms"] as? Int ?? 0,
                costUSD: object["total_cost_usd"] as? Double ?? 0,
                isError: object["is_error"] as? Bool ?? false,
                deniedTools: denials))]

        default:
            return [.ignored(type: type)]
        }
    }

    /// A short description of a tool call's input: file name, command, pattern, or URL.
    static func summary(of input: [String: Any]) -> String {
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            return (path as NSString).lastPathComponent
        }
        if let command = input["command"] as? String { return String(command.prefix(80)) }
        if let pattern = input["pattern"] as? String { return pattern }
        if let url = input["url"] as? String { return url }
        return ""
    }

    private static func contentBlocks(of object: [String: Any]) -> [[String: Any]] {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }
}
