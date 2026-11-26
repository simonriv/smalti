import Foundation

public enum RowKind: Equatable, Sendable {
    case prompt, reply, tool, image, compaction
}

/// One line of the timeline as the view paints it. Its texts already went through the `TranscriptTextPolicy`.
public struct TimelineRow: Equatable, Sendable {
    public let id: TimelineItemID
    public let depth: Int
    public let kind: RowKind
    public let who: String
    public let time: String?
    public let text: String
    public let isTruncated: Bool
    public let summary: String?
    public let status: ToolStatus?
    public let statusText: String?
    public let childCount: Int
    public let isExpanded: Bool
    public let expandedLabel: String?
    public let expandedText: String?
    public let moreLines: Int
    /// The parent tool of a subagent's row.
    public let parent: TimelineItemID?
}

/// Builds the rows from a timeline: the only way rows are made, so every text passes the policy (spec F9, C11).
public enum TimelineRows {
    /// Lines of an expanded output shown before "… N more lines".
    public static let expandedLines = 12

    private static let agentNames: [HarnessID: String] = [.claude: "Claude", .codex: "Codex"]

    public static func rows(
        _ timeline: Timeline, harness: HarnessID, expanded: Set<TimelineItemID>, policy: any TranscriptTextPolicy,
        texts: TimelineTexts, time: (Date) -> String
    ) -> [TimelineRow] {
        withoutActuallyEscaping(time) { time in
            let builder = Builder(
                agent: agentNames[harness] ?? harness.displayName, expanded: expanded, policy: policy, texts: texts,
                time: time)
            return timeline.turns.flatMap { turn in turn.items.flatMap { builder.rows(for: $0, depth: 0, parent: nil) }
            }
        }
    }

    private struct Builder {
        let agent: String
        let expanded: Set<TimelineItemID>
        let policy: any TranscriptTextPolicy
        let texts: TimelineTexts
        let time: (Date) -> String

        func rows(for item: TimelineItem, depth: Int, parent: TimelineItemID?) -> [TimelineRow] {
            switch item {
            case .prompt(let text): [plain(item.id, .prompt, texts.you, text.text, text.at, depth, parent)]
            case .reply(let text): [plain(item.id, .reply, agent, text.text, text.at, depth, parent)]
            case .image(let image):
                [note(item.id, .image, texts.image(["kind": image.image.mediaType]), image.at, depth, parent)]
            case .compaction(let note): [self.note(item.id, .compaction, compaction(note), nil, depth, parent)]
            case .tool(let tool): toolRows(tool, depth: depth, parent: parent)
            }
        }

        private func shown(_ text: String) -> String { policy.shown(text, as: .display) }

        private func plain(
            _ id: TimelineItemID, _ kind: RowKind, _ who: String, _ text: ExcerptText, _ at: Date?, _ depth: Int,
            _ parent: TimelineItemID?
        ) -> TimelineRow {
            TimelineRow(
                id: id, depth: depth, kind: kind, who: who, time: at.map(time), text: shown(text.excerpt),
                isTruncated: text.isTruncated, summary: nil, status: nil, statusText: nil, childCount: 0,
                isExpanded: false, expandedLabel: nil, expandedText: nil, moreLines: 0, parent: parent)
        }

        private func note(
            _ id: TimelineItemID, _ kind: RowKind, _ text: String, _ at: Date?, _ depth: Int, _ parent: TimelineItemID?
        ) -> TimelineRow {
            TimelineRow(
                id: id, depth: depth, kind: kind, who: "", time: at.map(time), text: text, isTruncated: false,
                summary: nil, status: nil, statusText: nil, childCount: 0, isExpanded: false, expandedLabel: nil,
                expandedText: nil, moreLines: 0, parent: parent)
        }

        private func compaction(_ note: CompactionNote) -> String {
            guard let before = note.preTokens, let after = note.postTokens else { return texts.compacted }
            return texts.compactedTokens(["before": Self.thousands(before), "after": Self.thousands(after)])
        }

        private static func thousands(_ tokens: Int) -> String {
            tokens >= 1_000 ? "\(tokens / 1_000)k" : "\(tokens)"
        }

        private func toolRows(_ tool: ToolItem, depth: Int, parent: TimelineItemID?) -> [TimelineRow] {
            let isOpen = expanded.contains(tool.id)
            let shownText = tool.result?.output ?? tool.call
            let lines = shownText.map { $0.excerpt.split(separator: "\n", omittingEmptySubsequences: false) } ?? []
            let visible = lines.prefix(TimelineRows.expandedLines).joined(separator: "\n")
            let row = TimelineRow(
                id: tool.id, depth: depth, kind: .tool, who: tool.name, time: tool.at.map(time), text: "",
                isTruncated: false,
                summary: shown(ToolSummary.text(name: tool.name, input: tool.arguments, diff: tool.result?.diff)),
                status: tool.status, statusText: statusText(tool.status), childCount: tool.children.count,
                isExpanded: isOpen, expandedLabel: isOpen ? (tool.result == nil ? texts.call : texts.output) : nil,
                expandedText: isOpen && shownText != nil ? shown(visible) : nil,
                moreLines: isOpen
                    ? max(0, (shownText?.lineCount ?? 0) - min(lines.count, TimelineRows.expandedLines)) : 0,
                parent: parent)
            guard isOpen else { return [row] }
            return [row] + tool.children.flatMap { rows(for: $0, depth: depth + 1, parent: tool.id) }
        }

        private func statusText(_ status: ToolStatus) -> String {
            switch status {
            case .working: texts.working
            case .done: texts.done
            case .failed(let code?): texts.errorExit(["code": String(code)])
            case .failed(nil): texts.error
            }
        }
    }
}
