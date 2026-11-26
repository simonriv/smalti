import Foundation

/// A session's transcript folded into turns (spec F9): a turn starts at each prompt, tool calls carry their results,
/// a subagent's entries nest under the call that launched it and compactions stay where they happened. It keeps
/// the entries (excerpts, not whole texts) and folds them again on each append, so reading in pieces always gives
/// what reading at once gives.
public struct Timeline: Equatable, Sendable {
    private var entries: [TranscriptEntry] = []
    public private(set) var turns: [TimelineTurn] = []

    public init() {}

    public func appending(_ new: [TranscriptEntry]) -> Timeline {
        var timeline = self
        timeline.entries += new
        timeline.turns = TimelineFold(timeline.entries).turns()
        return timeline
    }

    /// Turns opened by a prompt.
    public var turnCount: Int { turns.count { $0.prompt != nil } }

    /// Every tool, subagents' included.
    public var toolCount: Int { turns.flatMap(\.items).reduce(0) { $0 + Self.tools(in: $1) } }

    public var startedAt: Date? { entries.lazy.compactMap(\.at).first }

    public func item(_ id: TimelineItemID) -> TimelineItem? {
        Self.find(id, in: turns.flatMap(\.items))
    }

    private static func tools(in item: TimelineItem) -> Int {
        guard case .tool(let tool) = item else { return 0 }
        return 1 + tool.children.reduce(0) { $0 + tools(in: $1) }
    }

    private static func find(_ id: TimelineItemID, in items: [TimelineItem]) -> TimelineItem? {
        for item in items {
            if item.id == id { return item }
            if let found = find(id, in: item.children) { return found }
        }
        return nil
    }
}

/// One pass over all the entries: results and links first, then the main transcript in order.
private struct TimelineFold {
    private let main: [TranscriptEntry]
    private let subagents: [String: [TranscriptEntry]]
    private let subagentOrder: [String]
    private let results: [String: (ToolResultEntry, Date?)]
    private let calls: Set<String>
    private let links: [String: String]

    init(_ entries: [TranscriptEntry]) {
        var main: [TranscriptEntry] = []
        var subagents: [String: [TranscriptEntry]] = [:]
        var order: [String] = []
        var results: [String: (ToolResultEntry, Date?)] = [:]
        var calls: Set<String> = []
        var links: [String: String] = [:]
        for entry in entries {
            switch entry.kind {
            case .toolResult(let result): results[result.id] = (result, entry.at)
            case .toolCall(let call): calls.insert(call.id)
            case .subagentLink(let agent, let tool): links[tool] = agent
            default: break
            }
            switch entry.scope {
            case .main: main.append(entry)
            case .subagent(let agent):
                if subagents[agent] == nil { order.append(agent) }
                subagents[agent, default: []].append(entry)
            }
        }
        self.main = main
        self.subagents = subagents
        subagentOrder = order
        self.results = results
        self.calls = calls
        self.links = links
    }

    func turns() -> [TimelineTurn] {
        var turns: [[TimelineItem]] = []
        for entry in main {
            guard let item = item(for: entry) else { continue }
            if case .prompt = item { turns.append([]) }
            if turns.isEmpty { turns.append([]) }
            turns[turns.count - 1].append(item)
        }
        let linked = Set(links.values)
        let loose = subagentOrder.filter { !linked.contains($0) }.map { agent in
            TimelineItem.tool(
                ToolItem(
                    id: .agent(agent), name: "Agent", arguments: [:], call: nil, result: nil,
                    children: items(of: subagents[agent] ?? []), at: subagents[agent]?.first?.at))
        }
        if !loose.isEmpty { turns.append(loose) }
        return turns.map(TimelineTurn.init(items:))
    }

    private func items(of entries: [TranscriptEntry]) -> [TimelineItem] {
        entries.compactMap(item(for:))
    }

    private func item(for entry: TranscriptEntry) -> TimelineItem? {
        switch entry.kind {
        case .prompt(let text): .prompt(TimedText(text: text, at: entry.at))
        case .reply(let text): .reply(TimedText(text: text, at: entry.at))
        case .image(let image): .image(TimedImage(image: image, at: entry.at))
        case .compaction(let note): .compaction(note)
        case .toolCall(let call): .tool(tool(for: call, at: entry.at))
        case .toolResult(let result) where !calls.contains(result.id):
            .tool(
                ToolItem(
                    id: .tool(result.id), name: "", arguments: [:], call: nil, result: result, children: [],
                    at: entry.at))
        case .toolResult, .subagentLink: nil
        }
    }

    private func tool(for call: ToolCallEntry, at: Date?) -> ToolItem {
        let children = links[call.id].map { items(of: subagents[$0] ?? []) } ?? []
        return ToolItem(
            id: .tool(call.id), name: call.name, arguments: call.arguments, call: call.call,
            result: results[call.id]?.0, children: children, at: at)
    }
}
