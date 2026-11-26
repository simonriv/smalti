import Foundation
import SmaltiCore

/// Translates Claude Code transcript lines into timeline entries (spec F9, section 1; format checked against
/// 2.1.330). Each text is located by its line and block so it can be read again whole; `text(of:block:field:)` is the
/// one rule for what a place holds, used both to build the excerpt and to copy.
struct ClaudeTimelineTranslator {
    /// An entry and, for prompts, replies, calls and outputs, its whole text (search confirms on it).
    struct Translated {
        let entry: TranscriptEntry
        let text: String?
    }

    /// The prompt: the string content, or all text blocks joined.
    static let promptBlock = -1
    /// Lines without any of these say nothing to the timeline and are not parsed.
    private static let markers = ["\"user\"", "\"assistant\"", "compact_boundary"].map { Data($0.utf8) }
    private static let exitCodePrefix = "Exit code "
    private static let agentIDPrefix = "agentId: "
    static let argumentLimit = 200

    let file: String
    let inode: UInt64
    let scope: EntryScope

    func translate(_ line: Data, at offset: UInt64) -> [Translated] {
        guard Self.markers.contains(where: { line.range(of: $0) != nil }),
            let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return [] }
        let place = Place(file: file, inode: inode, offset: offset, length: line.count)
        let at = Self.date(record)
        switch record["type"] as? String {
        case "assistant": return assistant(record, place, at)
        case "user": return user(record, place, at)
        case "system": return compaction(record, place, at)
        default: return []
        }
    }

    // MARK: - The texts of a place

    static func text(of record: [String: Any], block: Int, field: TextField) -> String? {
        let content = (record["message"] as? [String: Any])?["content"]
        if block == promptBlock { return promptText(content) }
        guard let blocks = content as? [[String: Any]], blocks.indices.contains(block) else {
            return field == .text && block == 0 && record["type"] as? String == "system" ? "" : nil
        }
        let piece = blocks[block]
        switch field {
        case .text: return piece["text"] as? String
        case .toolInput: return canonical(piece["input"] ?? [String: Any]())
        case .toolOutput: return outputText(piece["content"])
        case .image: return nil
        }
    }

    private static func promptText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        let texts = (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    static func outputText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        return (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    /// A call as compact JSON with sorted keys: Foundation cannot keep the file's key order (the oracle does the same).
    static func canonical(_ value: Any) -> String {
        CanonicalJSON.string(value)
    }

    // MARK: - Lines

    private struct Place {
        let file: String
        let inode: UInt64
        let offset: UInt64
        let length: Int

        func location(_ block: Int, _ field: TextField, item: Int = 0) -> TextLocation {
            TextLocation(
                file: file, inode: inode, offset: offset, length: length, block: block, field: field, item: item)
        }
    }

    private func entry(_ kind: TranscriptEntry.Kind, _ at: Date?, text: String? = nil) -> Translated {
        Translated(entry: TranscriptEntry(kind: kind, scope: scope, at: at), text: text)
    }

    private func excerpt(_ text: String, _ place: Place, _ block: Int, _ field: TextField) -> ExcerptText {
        ExcerptText.make(full: text, location: place.location(block, field))
    }

    private func assistant(_ record: [String: Any], _ place: Place, _ at: Date?) -> [Translated] {
        let blocks = (record["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        return blocks.enumerated().compactMap { index, block in
            switch block["type"] as? String {
            case "text":
                let text = block["text"] as? String ?? ""
                return entry(.reply(excerpt(text, place, index, .text)), at, text: text)
            case "tool_use":
                let call = Self.text(of: record, block: index, field: .toolInput) ?? ""
                let arguments = (block["input"] as? [String: Any] ?? [:]).compactMapValues {
                    ($0 as? String).map { String($0.prefix(Self.argumentLimit)) }
                }
                return entry(
                    .toolCall(
                        ToolCallEntry(
                            id: block["id"] as? String ?? "", name: block["name"] as? String ?? "",
                            arguments: arguments, call: excerpt(call, place, index, .toolInput))), at, text: call)
            default: return nil
            }
        }
    }

    private func user(_ record: [String: Any], _ place: Place, _ at: Date?) -> [Translated] {
        guard record["isMeta"] as? Bool != true, record["isCompactSummary"] as? Bool != true else { return [] }
        let content = (record["message"] as? [String: Any])?["content"]
        var translated: [Translated] = []
        if let prompt = Self.promptText(content) {
            translated.append(entry(.prompt(excerpt(prompt, place, Self.promptBlock, .text)), at, text: prompt))
        }
        for (index, block) in (content as? [[String: Any]] ?? []).enumerated() {
            switch block["type"] as? String {
            case "image": translated.append(image(block, place, index, at))
            case "tool_result": translated += result(block, record["toolUseResult"], place, index, at)
            default: break
            }
        }
        return translated
    }

    private func image(_ block: [String: Any], _ place: Place, _ index: Int, _ at: Date?, item: Int = 0) -> Translated {
        let source = block["source"] as? [String: Any] ?? [:]
        let data = source["data"] as? String ?? ""
        let padding = data.suffix(2).filter { $0 == "=" }.count
        return entry(
            .image(
                ImageNote(
                    mediaType: source["media_type"] as? String ?? "", byteCount: max(0, data.count * 3 / 4 - padding),
                    location: place.location(index, .image, item: item))), at)
    }

    private func result(_ block: [String: Any], _ extra: Any?, _ place: Place, _ index: Int, _ at: Date?)
        -> [Translated]
    {
        let id = block["tool_use_id"] as? String ?? ""
        let output = Self.outputText(block["content"])
        let isError = block["is_error"] as? Bool ?? false
        var translated = [
            entry(
                .toolResult(
                    ToolResultEntry(
                        id: id, isError: isError, exitCode: isError ? Self.exitCode(output) : nil,
                        diff: Self.diff(extra), output: excerpt(output, place, index, .toolOutput))), at, text: output)
        ]
        let images = (block["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "image" }
        translated += images.enumerated().map { image($1, place, index, at, item: $0 + 1) }
        if let agent = Self.agentID(output, extra) {
            translated.append(entry(.subagentLink(agentID: agent, toolID: id), at))
        }
        return translated
    }

    private func compaction(_ record: [String: Any], _ place: Place, _ at: Date?) -> [Translated] {
        guard record["subtype"] as? String == "compact_boundary" else { return [] }
        let metadata = record["compactMetadata"] as? [String: Any] ?? [:]
        return [
            entry(
                .compaction(
                    CompactionNote(
                        preTokens: (metadata["preTokens"] as? NSNumber)?.intValue,
                        postTokens: (metadata["postTokens"] as? NSNumber)?.intValue,
                        location: place.location(0, .text))), at)
        ]
    }

    // MARK: - Details

    private static func exitCode(_ output: String) -> Int? {
        guard output.hasPrefix(exitCodePrefix) else { return nil }
        return Int(output.dropFirst(exitCodePrefix.count).prefix { $0.isNumber })
    }

    private static func diff(_ extra: Any?) -> DiffStat? {
        guard let hunks = (extra as? [String: Any])?["structuredPatch"] as? [[String: Any]] else { return nil }
        let lines = hunks.flatMap { $0["lines"] as? [String] ?? [] }
        return DiffStat(added: lines.count { $0.hasPrefix("+") }, removed: lines.count { $0.hasPrefix("-") })
    }

    /// The subagent an `Agent` result launched: `toolUseResult.agentId`, or `agentId: <id>` in its text.
    private static func agentID(_ output: String, _ extra: Any?) -> String? {
        if let id = (extra as? [String: Any])?["agentId"] as? String { return id }
        guard let range = output.range(of: agentIDPrefix) else { return nil }
        let id = output[range.upperBound...].prefix { $0.isLetter || $0.isNumber }
        return id.isEmpty ? nil : String(id)
    }

    static func date(_ record: [String: Any]) -> Date? {
        ClaudeSessionList.timestamp(record)
    }
}
