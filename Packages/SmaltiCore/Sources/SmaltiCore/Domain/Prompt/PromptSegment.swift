/// A color role of the theme; the renderer turns it into the theme's (protected) color.
public enum SegmentColor: Hashable, Sendable {
    case accent
    case ansi(Int)
    case secondary
    case waiting
    case failed
}

public struct ColoredText: Equatable, Sendable {
    public let text: String
    public let color: SegmentColor

    public init(_ text: String, _ color: SegmentColor) {
        self.text = text
        self.color = color
    }
}

/// The thin-stroke icons of `SmaltiSymbols`, in the font's order (U+E900 onward).
public enum PromptIcon: CaseIterable, Sendable {
    case folder, branch, node, bun, python, go, clock, kubernetes, cloud
}

/// What one module shows: an optional icon and one or more colored pieces of text ("●2" ámbar, "+1" verde).
public struct PromptSegment: Equatable, Sendable {
    public let module: PromptModuleID
    public let icon: PromptIcon?
    public let runs: [ColoredText]

    public init(module: PromptModuleID, icon: PromptIcon?, runs: [ColoredText]) {
        self.module = module
        self.icon = icon
        self.runs = runs
    }

    public var text: String { runs.map(\.text).joined() }

    /// The segment's own color: the first piece's (pills tint with it).
    public var leadingColor: SegmentColor { runs.first?.color ?? .secondary }
}
