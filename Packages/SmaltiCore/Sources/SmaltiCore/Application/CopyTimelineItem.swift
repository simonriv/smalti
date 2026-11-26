/// What ⌘C copies of a tool: its output (or its call while it has none), or ⇧⌘C its call.
public enum CopyPart: Sendable {
    case content
    case call
}

public struct CopiedText: Equatable, Sendable {
    public let text: String
    public let byteCount: Int

    init(_ text: String) {
        self.text = text
        byteCount = text.utf8.count
    }
}

/// Copies a timeline item whole, read again from the transcript (never from the painted excerpt), through the
/// text policy (spec F9, section 5).
public struct CopyTimelineItem: Sendable {
    private let sources: TranscriptSources
    private let policy: any TranscriptTextPolicy
    private let texts: TimelineTexts

    public init(sources: TranscriptSources, policy: any TranscriptTextPolicy, texts: TimelineTexts) {
        self.sources = sources
        self.policy = policy
        self.texts = texts
    }

    /// nil when there is nothing to copy (⇧⌘C on something without a call).
    public func copy(_ id: TimelineItemID, in timeline: Timeline, harness: HarnessID, part: CopyPart)
        async throws(TranscriptReadError) -> CopiedText?
    {
        guard let item = timeline.item(id) else { throw .missing(path: id.rawValue) }
        switch item {
        // Described, not read: the same for every harness (review 1, I2 and M13).
        case .image(let image):
            return part == .content ? CopiedText(texts.imageDescription(image.image)) : nil
        case .compaction(let note):
            return part == .content ? CopiedText(texts.compaction(note)) : nil
        case .prompt(let text), .reply(let text):
            return part == .content ? try await copy(at: text.text.location, harness: harness) : nil
        case .tool(let tool):
            let source = part == .call ? tool.call : tool.result?.output ?? tool.call
            guard let source else { return nil }
            return try await copy(at: source.location, harness: harness)
        }
    }

    /// A search result's text, by its place.
    public func copy(at location: TextLocation, harness: HarnessID) async throws(TranscriptReadError) -> CopiedText {
        guard let transcripts = sources.session(harness) else { throw .missing(path: location.file) }
        return CopiedText(policy.shown(try await transcripts.fullText(at: location), as: .copy))
    }
}
