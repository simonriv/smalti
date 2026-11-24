/// "Línea limpia" and "Una sola línea": segments in their colors, three spaces apart, as on the board.
public struct CleanStyle: PromptStyle {
    public let id = PromptStyleID.clean
    static let gap = "   "

    public init() {}

    public func lines(_ segments: [PromptSegment], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]] {
        var context: [StyledRun] = []
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                let joinsBranch = segment.module == .gitStatus && segments[index - 1].module == .gitBranch
                context.append(StyledRun(.text(joinsBranch ? " " : Self.gap), .secondary))
            }
            context += runs(of: segment)
        }
        return arrange(context: context, symbol: symbol, layout: layout)
    }
}

/// "Píldoras": each segment on its own color at 16 %, one space apart.
public struct PillsStyle: PromptStyle {
    public let id = PromptStyleID.pills
    static let tint = 0.16

    public init() {}

    public func lines(_ segments: [PromptSegment], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]] {
        let pills = segments.map { segment -> [StyledRun] in
            let tint = segment.leadingColor
            let pad = StyledRun(.text(" "), tint, background: tint)
            return [pad] + runs(of: segment, background: tint) + [pad]
        }
        let context = pills.enumerated().flatMap { index, pill in
            index == 0 ? pill : [StyledRun(.text(" "), .secondary)] + pill
        }
        return arrange(context: context, symbol: symbol, layout: layout)
    }

    /// zsh has no transparency: the pill's background is its color at 16 % over the panel, as one opaque color.
    public static func background(of color: RGBAColor, over panel: RGBAColor) -> RGBAColor {
        panel.withAlpha(1).underneath(color.withAlpha(tint))
    }
}

/// "Solo símbolo": the line carries only the symbol; the context goes to the pane header (`PromptHeaderText`).
public struct SymbolOnlyStyle: PromptStyle {
    public let id = PromptStyleID.symbolOnly

    public init() {}

    public func lines(_ segments: [PromptSegment], symbol: SymbolSegment, layout: PromptLayout) -> [[StyledRun]] {
        [symbol.runs]
    }
}
