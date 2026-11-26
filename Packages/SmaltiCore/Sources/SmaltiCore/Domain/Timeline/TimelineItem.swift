import Foundation

public struct TimelineItemID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func tool(_ id: String) -> TimelineItemID { TimelineItemID(rawValue: "tool:\(id)") }
    public static func agent(_ id: String) -> TimelineItemID { TimelineItemID(rawValue: "agent:\(id)") }
    public static func at(_ location: TextLocation) -> TimelineItemID { TimelineItemID(rawValue: location.key) }
}

/// A prompt or a reply with its time.
public struct TimedText: Equatable, Sendable {
    public let text: ExcerptText
    public let at: Date?
}

public struct TimedImage: Equatable, Sendable {
    public let image: ImageNote
    public let at: Date?
}

public enum ToolStatus: Equatable, Sendable {
    case working
    case done
    case failed(exitCode: Int?)
}

/// A tool call with its result, if it came, and what its subagent did.
public struct ToolItem: Equatable, Sendable {
    public let id: TimelineItemID
    /// Empty for a result whose call is not in the transcript.
    public let name: String
    public let arguments: [String: String]
    public let call: ExcerptText?
    public let result: ToolResultEntry?
    public let children: [TimelineItem]
    public let at: Date?

    public var status: ToolStatus {
        guard let result else { return .working }
        return result.isError ? .failed(exitCode: result.exitCode) : .done
    }
}

public indirect enum TimelineItem: Equatable, Sendable {
    case prompt(TimedText)
    case reply(TimedText)
    case tool(ToolItem)
    case image(TimedImage)
    case compaction(CompactionNote)

    public var id: TimelineItemID {
        switch self {
        case .prompt(let text), .reply(let text): .at(text.text.location)
        case .tool(let tool): tool.id
        case .image(let image): .at(image.image.location)
        case .compaction(let note): .at(note.location)
        }
    }

    var children: [TimelineItem] {
        if case .tool(let tool) = self { tool.children } else { [] }
    }
}

public struct TimelineTurn: Equatable, Sendable {
    public let items: [TimelineItem]

    /// The prompt that opened the turn; nil for what came before the first prompt.
    public var prompt: TimedText? {
        if case .prompt(let text) = items.first { text } else { nil }
    }
}
