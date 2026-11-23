import Foundation
import SmaltiCore

/// What one line of a transcript says, in the domain's words. Unknown record types say nothing.
struct TranslatedLine {
    var records: [TranscriptRecord] = []
    /// Sessions this one was forked from (`derived-from`), whose copied replies it must not count.
    var derivedFrom: [String] = []
}

/// Translates Claude Code transcript lines (JSONL, undocumented format checked against 2.1.330).
struct TranscriptLineTranslator {
    struct UnreadableLine: Error {}

    /// Lines without any of these words carry nothing the observatory reads, and are not parsed at all.
    private static let markers = ["\"assistant\"", "\"tool_result\"", "\"compact_boundary\"", "\"derived-from\""]
        .map { Data($0.utf8) }
    private static let exitCodePrefix = "Exit code "

    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let whole = ISO8601DateFormatter()

    func translate(_ line: Data, isSubagent: Bool) throws(UnreadableLine) -> TranslatedLine {
        guard Self.markers.contains(where: { line.range(of: $0) != nil }) else { return TranslatedLine() }
        guard let object = try? JSONSerialization.jsonObject(with: line), let record = object as? [String: Any] else {
            throw UnreadableLine()
        }
        switch record["type"] as? String {
        case "assistant": return TranslatedLine(records: assistant(record, isSubagent: isSubagent))
        case "user": return TranslatedLine(records: toolResults(record, isSubagent: isSubagent))
        case "system": return TranslatedLine(records: compaction(record).map { [$0] } ?? [])
        case "derived-from": return TranslatedLine(derivedFrom: sources(record))
        default: return TranslatedLine()
        }
    }

    private func date(_ record: [String: Any]) -> Date? {
        guard let text = record["timestamp"] as? String else { return nil }
        return fractional.date(from: text) ?? whole.date(from: text)
    }

    private func assistant(_ record: [String: Any], isSubagent: Bool) -> [TranscriptRecord] {
        guard let at = date(record), let message = record["message"] as? [String: Any] else { return [] }
        var records: [TranscriptRecord] = []
        if let session = record["sessionId"] as? String, let cwd = record["cwd"] as? String, !isSubagent {
            records.append(.sessionInfo(sessionID: session, cwd: cwd, at: at))
        }
        if let id = message["id"] as? String, let model = message["model"] as? String,
            let usage = message["usage"] as? [String: Any]
        {
            records.append(
                .assistantTurn(
                    AssistantTurn(
                        messageID: id, model: ModelID(rawValue: model), usage: tokens(usage), at: at,
                        isSubagent: isSubagent)))
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        records += blocks.compactMap { toolStart($0, at: at, isSubagent: isSubagent) }
        return records
    }

    private func tokens(_ usage: [String: Any]) -> TokenUsage {
        let writes = count("cache_creation_input_tokens", in: usage)
        let breakdown = usage["cache_creation"] as? [String: Any]
        return TokenUsage(
            input: count("input_tokens", in: usage), output: count("output_tokens", in: usage),
            cacheRead: count("cache_read_input_tokens", in: usage),
            cacheWrite5m: breakdown.map { count("ephemeral_5m_input_tokens", in: $0) } ?? writes,
            cacheWrite1h: breakdown.map { count("ephemeral_1h_input_tokens", in: $0) } ?? 0)
    }

    private func count(_ key: String, in source: [String: Any]) -> Int {
        (source[key] as? NSNumber)?.intValue ?? 0
    }

    private func toolStart(_ block: [String: Any], at: Date, isSubagent: Bool) -> TranscriptRecord? {
        guard block["type"] as? String == "tool_use", let id = block["id"] as? String,
            let name = block["name"] as? String
        else { return nil }
        let input = (block["input"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        return .toolStarted(ToolStart(id: id, name: name, input: input, at: at, isSubagent: isSubagent))
    }

    private func toolResults(_ record: [String: Any], isSubagent: Bool) -> [TranscriptRecord] {
        guard let at = date(record), let message = record["message"] as? [String: Any],
            let blocks = message["content"] as? [[String: Any]]
        else { return [] }
        let diff = diffStat(record["toolUseResult"])
        return blocks.compactMap { block in
            guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else {
                return nil
            }
            let isError = block["is_error"] as? Bool ?? false
            return .toolFinished(
                ToolFinish(
                    id: id, isError: isError, exitCode: isError ? exitCode(block["content"]) : nil, diff: diff, at: at,
                    isSubagent: isSubagent))
        }
    }

    private func exitCode(_ content: Any?) -> Int? {
        let text: String
        if let string = content as? String {
            text = string
        } else {
            text = (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        }
        guard text.hasPrefix(Self.exitCodePrefix) else { return nil }
        return Int(text.dropFirst(Self.exitCodePrefix.count).prefix { $0.isNumber })
    }

    private func diffStat(_ result: Any?) -> DiffStat? {
        guard let hunks = (result as? [String: Any])?["structuredPatch"] as? [[String: Any]] else { return nil }
        let lines = hunks.flatMap { $0["lines"] as? [String] ?? [] }
        return DiffStat(
            added: lines.filter { $0.hasPrefix("+") }.count, removed: lines.filter { $0.hasPrefix("-") }.count)
    }

    private func compaction(_ record: [String: Any]) -> TranscriptRecord? {
        guard record["subtype"] as? String == "compact_boundary", let at = date(record),
            let metadata = record["compactMetadata"] as? [String: Any],
            let pre = (metadata["preTokens"] as? NSNumber)?.intValue,
            let post = (metadata["postTokens"] as? NSNumber)?.intValue
        else { return nil }
        return .compacted(Compaction(at: at, preTokens: pre, postTokens: post))
    }

    private func sources(_ record: [String: Any]) -> [String] {
        (record["sessions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }
}
