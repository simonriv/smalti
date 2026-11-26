/// What ⌘C copies of a tool: its output (or its call while it has none), or ⇧⌘C its call.
public enum CopyPart: Sendable {
    case content
    case call
}

public struct CopiedText: Equatable, Sendable {
    public let text: String
    public let byteCount: Int
}

/// Copies a timeline item whole, read again from the transcript (never from the painted excerpt), through the
/// text policy (spec F9, section 5).
public struct CopyTimelineItem: Sendable {
    private let sources: TranscriptSources
    private let policy: any TranscriptTextPolicy

    public init(sources: TranscriptSources, policy: any TranscriptTextPolicy) {
        self.sources = sources
        self.policy = policy
    }

    public func copy(_ id: TimelineItemID, in timeline: Timeline, harness: HarnessID, part: CopyPart)
        async throws(TranscriptReadError) -> CopiedText
    {
        guard let item = timeline.item(id), let location = Self.location(of: item, part: part) else {
            throw .missing(path: id.rawValue)
        }
        return try await copy(at: location, harness: harness)
    }

    /// A search result's text, by its place.
    public func copy(at location: TextLocation, harness: HarnessID) async throws(TranscriptReadError) -> CopiedText {
        guard let transcripts = sources.session(harness) else { throw .missing(path: location.file) }
        let text = policy.shown(try await transcripts.fullText(at: location), as: .copy)
        return CopiedText(text: text, byteCount: text.utf8.count)
    }

    static func location(of item: TimelineItem, part: CopyPart) -> TextLocation? {
        switch item {
        case .prompt(let text), .reply(let text): text.text.location
        case .tool(let tool) where part == .call: (tool.call ?? tool.result?.output)?.location
        case .tool(let tool): (tool.result?.output ?? tool.call)?.location
        case .image(let image): image.image.location
        case .compaction(let note): note.location
        }
    }
}
