import Foundation
import SmaltiCore

/// Translates Codex rollout lines into timeline entries (spec F9, section 1; checked against codex-cli 0.172.0).
/// Only `response_item` and `compacted` lines count: `event_msg` repeats them. `text(of:field:)` is the one rule for
/// what a line holds, used both for the excerpt and to copy.
struct CodexTimelineTranslator {
    struct Translated {
        let entry: TranscriptEntry
        let text: String?
    }

    /// Context Codex injects as user messages: not prompts.
    private static let contextPrefixes = ["<environment_context>", "<user_instructions>", "<skills_instructions>"]
    private static let markers = ["\"response_item\"", "\"compacted\""].map { Data($0.utf8) }
    private static let exitPrefix = "Process exited with code "
    static let argumentLimit = 200

    let file: String
    let inode: UInt64

    func translate(_ line: Data, at offset: UInt64) -> [Translated] {
        guard Self.markers.contains(where: { line.range(of: $0) != nil }),
            let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return [] }
        let location = { (field: TextField) in
            TextLocation(file: file, inode: inode, offset: offset, length: line.count, block: 0, field: field)
        }
        let at = (record["timestamp"] as? String).flatMap {
            try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0)
        }
        let payload = record["payload"] as? [String: Any] ?? [:]
        if record["type"] as? String == "compacted" {
            return [entry(.compaction(CompactionNote(preTokens: nil, postTokens: nil, location: location(.text))), at)]
        }
        guard record["type"] as? String == "response_item" else { return [] }
        switch payload["type"] as? String {
        case "message": return message(record, payload, location, at)
        case "function_call", "custom_tool_call": return call(record, payload, location, at)
        case "function_call_output", "custom_tool_call_output": return output(record, payload, location, at)
        default: return []
        }
    }

    // MARK: - The texts of a line

    static func text(of record: [String: Any], field: TextField) -> String? {
        let payload = record["payload"] as? [String: Any] ?? [:]
        switch (payload["type"] as? String, field) {
        case ("message", .text): return messageText(payload)
        case ("function_call", .toolInput): return payload["arguments"] as? String ?? ""
        case ("custom_tool_call", .toolInput): return payload["input"] as? String ?? ""
        case ("function_call_output", .toolOutput), ("custom_tool_call_output", .toolOutput):
            return outputText(payload)
        default: return nil
        }
    }

    private static func messageText(_ payload: [String: Any]) -> String? {
        let kind = payload["role"] as? String == "assistant" ? "output_text" : "input_text"
        let texts = (payload["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == kind }
            .compactMap { $0["text"] as? String }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static func outputText(_ payload: [String: Any]) -> String {
        if let text = payload["output"] as? String { return text }
        return (payload["output"] as? [String: Any])?["content"] as? String ?? ""
    }

    // MARK: - Lines

    private func entry(_ kind: TranscriptEntry.Kind, _ at: Date?, text: String? = nil) -> Translated {
        Translated(entry: TranscriptEntry(kind: kind, scope: .main, at: at), text: text)
    }

    private func message(
        _ record: [String: Any], _ payload: [String: Any], _ location: (TextField) -> TextLocation, _ at: Date?
    ) -> [Translated] {
        guard let text = Self.messageText(payload) else { return [] }
        let excerpt = ExcerptText.make(full: text, location: location(.text))
        switch payload["role"] as? String {
        case "assistant": return [entry(.reply(excerpt), at, text: text)]
        case "user" where !Self.contextPrefixes.contains(where: text.trimmingCharacters(in: .whitespaces).hasPrefix):
            return [entry(.prompt(excerpt), at, text: text)]
        default: return []
        }
    }

    private func call(
        _ record: [String: Any], _ payload: [String: Any], _ location: (TextField) -> TextLocation, _ at: Date?
    ) -> [Translated] {
        let text = Self.text(of: record, field: .toolInput) ?? ""
        let arguments: [String: String] =
            payload["type"] as? String == "custom_tool_call"
            ? ["input": String(text.prefix(Self.argumentLimit))] : Self.arguments(text)
        return [
            entry(
                .toolCall(
                    ToolCallEntry(
                        id: payload["call_id"] as? String ?? "", name: payload["name"] as? String ?? "",
                        arguments: arguments, call: ExcerptText.make(full: text, location: location(.toolInput)))),
                at, text: text)
        ]
    }

    private static func arguments(_ json: String) -> [String: String] {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            return [:]
        }
        return object.compactMapValues { ($0 as? String).map { String($0.prefix(argumentLimit)) } }
    }

    private func output(
        _ record: [String: Any], _ payload: [String: Any], _ location: (TextField) -> TextLocation, _ at: Date?
    ) -> [Translated] {
        let text = Self.outputText(payload)
        let code = Self.exitCode(text)
        return [
            entry(
                .toolResult(
                    ToolResultEntry(
                        id: payload["call_id"] as? String ?? "", isError: (code ?? 0) != 0, exitCode: code, diff: nil,
                        output: ExcerptText.make(full: text, location: location(.toolOutput)))), at, text: text)
        ]
    }

    private static func exitCode(_ output: String) -> Int? {
        guard let range = output.range(of: exitPrefix) else { return nil }
        return Int(output[range.upperBound...].prefix { $0.isNumber || $0 == "-" })
    }
}
