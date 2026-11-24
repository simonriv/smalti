/// A piece of a prompt line: text or an icon, with its color role and, for pills, the role it is tinted with.
public struct StyledRun: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        case icon(PromptIcon)
        /// The prompt symbol, kept apart so the renderer can name it once for every prompt (`_smalti_sym`).
        case symbol(PromptSymbol)
    }

    public let content: Content
    public let color: SegmentColor
    /// Pills: the role whose 16 % tint is the background (`PillsStyle.background`).
    public let background: SegmentColor?

    public init(_ content: Content, _ color: SegmentColor, background: SegmentColor? = nil) {
        self.content = content
        self.color = color
        self.background = background
    }
}

/// The symbol, red with `exit N` after it when the last command failed (spec F5, "Después de un error").
public struct SymbolSegment: Equatable, Sendable {
    public let symbol: PromptSymbol
    public let lastExit: Int

    public init(symbol: PromptSymbol, lastExit: Int) {
        self.symbol = symbol
        self.lastExit = lastExit
    }

    var runs: [StyledRun] {
        let failed = lastExit != 0
        let exit = failed ? [StyledRun(.text(" exit \(lastExit)"), .secondary)] : []
        return [StyledRun(.symbol(symbol), failed ? .failed : .accent)] + exit
            + [StyledRun(.text(" "), .secondary)]
    }
}

/// One way to lay out the segments (spec F5: Limpio, Píldoras, Solo símbolo), a type per style.
public protocol PromptStyle: Sendable {
    var id: PromptStyleID { get }
    func lines(_ segments: [PromptSegment], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]]
}

/// The styles by identifier.
public enum PromptStyles {
    private static let all: [PromptStyleID: any PromptStyle] = Dictionary(
        uniqueKeysWithValues: ([CleanStyle(), PillsStyle(), SymbolOnlyStyle()] as [any PromptStyle]).map { ($0.id, $0) }
    )

    public static func style(for id: PromptStyleID) -> any PromptStyle {
        // Every identifier has its style (`everyStyleIdHasItsStyle`); the fallback is never reached.
        all[id] ?? CleanStyle()
    }
}

/// Context on one line, or above the symbol.
func arrange(context: [StyledRun], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]] {
    guard !context.isEmpty else { return [symbol.runs] }
    switch layout {
    case .twoLines: return [context, symbol.runs]
    case .oneLine: return [context + [StyledRun(.text(" "), .secondary)] + symbol.runs]
    }
}

/// The icon (and its space) followed by the segment's pieces.
func runs(of segment: PromptSegment, background: SegmentColor? = nil) -> [StyledRun] {
    let color = segment.leadingColor
    let icon = segment.icon.map {
        [StyledRun(.icon($0), color, background: background), StyledRun(.text(" "), color, background: background)]
    }
    return (icon ?? []) + segment.runs.map { StyledRun(.text($0.text), $0.color, background: background) }
}
