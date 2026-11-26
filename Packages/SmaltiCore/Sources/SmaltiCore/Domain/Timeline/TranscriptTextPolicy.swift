/// Where a transcript text is going.
public enum TranscriptTextContext: Hashable, Sendable {
    case display
    case copy
    case searchSnippet
}

/// Port (F9): the one place every transcript text passes before it is painted, copied or shown as a search snippet.
/// F11 masks secrets here without touching the view; F9 shows texts as they are.
public protocol TranscriptTextPolicy: Sendable {
    func shown(_ text: String, as context: TranscriptTextContext) -> String
}

/// F9's policy: the text as the agent wrote it.
public struct VerbatimText: TranscriptTextPolicy {
    public init() {}

    public func shown(_ text: String, as context: TranscriptTextContext) -> String { text }
}
