/// The two prompt strings zsh shows (spec F5, "Del dominio a zsh"). The *immediate* one uses zsh's own expansions
/// for local facts and is painted at once; the *full* one carries everything once Smalti answers. Outside text never
/// enters the strings: it goes to `values`, which the script assigns to variables the strings reference, so `$(…)` in
/// a branch name is shown, never run (the script turns on `prompt_subst` for those references).
public enum ZshPromptRenderer {
    static let symbolVariable = "_smalti_sym"

    public static func render(_ config: PromptConfig, context: PromptContext, theme: AppliedTheme) -> RenderedPrompt {
        let palette = ZshPalette(theme: theme.theme, icons: config.icons, isPills: config.style == .pills)
        let style = PromptStyles.style(for: config.style)
        let symbol = SymbolSegment(symbol: config.symbol, lastExit: context.lastExit)
        let lines = style.lines(PromptModules.segments(for: config, in: context), symbol: symbol, layout: config.layout)
        var values = ValueTable()
        let full = lines.map { line in palette.drawable(line).map { palette.paint($0, values: &values) }.joined() }
            .joined(separator: "\n")
        let label = DirectoryLabel.label(directory: context.directory, home: context.home, repoRoot: context.repoRoot)
        values.assign(symbolVariable, config.symbol.rawValue)
        return RenderedPrompt(
            immediate: immediate(config, palette: palette), full: full, values: values.entries,
            directoryLabel: ZshEscaping.literal(label))
    }

    private static func immediate(_ config: PromptConfig, palette: ZshPalette) -> String {
        let parts =
            config.style == .symbolOnly ? [] : config.modules.compactMap { PromptModules.module(for: $0).immediate }
        let gap = config.style == .pills ? " " : CleanStyle.gap
        let context = parts.enumerated().map { index, part in palette.paint(part, gap: index == 0 ? "" : gap) }.joined()
        let symbol = palette.conditionalSymbol()
        guard !context.isEmpty else { return symbol }
        return context + (config.layout == .twoLines ? "\n" : " ") + symbol
    }
}

/// What the script receives: both strings, the values they reference, and the directory label it remembers for the
/// next immediate prompt in the same directory.
public struct RenderedPrompt: Equatable, Sendable {
    public let immediate: String
    public let full: String
    public let values: [String: String]
    public let directoryLabel: String

    public init(immediate: String, full: String, values: [String: String], directoryLabel: String) {
        self.immediate = immediate
        self.full = full
        self.values = values
        self.directoryLabel = directoryLabel
    }
}

/// `_smalti_p_1`, `_smalti_p_2`… in order of appearance.
private struct ValueTable {
    private(set) var entries: [String: String] = [:]
    private var count = 0

    mutating func reference(_ text: String) -> String {
        count += 1
        let name = "_smalti_p_\(count)"
        entries[name] = ZshEscaping.literal(text)
        return "${\(name)}"
    }

    mutating func assign(_ name: String, _ text: String) {
        entries[name] = ZshEscaping.literal(text)
    }
}

/// Color roles and icons turned into zsh prompt escapes with the theme's (protected) colors.
private struct ZshPalette {
    let theme: Theme
    let icons: PromptIcons
    /// Immediate pieces wear their pill too, so the prompt does not jump when Smalti answers.
    let isPills: Bool

    func color(_ role: SegmentColor) -> RGBAColor {
        theme.color(for: role)
    }

    private func foreground(_ role: SegmentColor, _ text: String) -> String {
        "%F{\(color(role).hexString)}\(text)%f"
    }

    func drawable(_ line: [StyledRun]) -> [StyledRun] {
        drawableRuns(line, icons: icons)
    }

    func paint(_ run: StyledRun, values: inout ValueTable) -> String {
        let body: String
        switch run.content {
        case .icon(let icon):
            guard let character = icons.character(for: icon) else { return "" }
            body = foreground(run.color, String(character))
        case .symbol:
            body = foreground(run.color, "${\(ZshPromptRenderer.symbolVariable)}")
        case .text(let text) where text.allSatisfy { $0 == " " }:
            body = text
        case .text(let text):
            body = foreground(run.color, values.reference(text))
        }
        return run.background.map { "%K{\(background($0))}\(body)%k" } ?? body
    }

    private func background(_ role: SegmentColor) -> String {
        PillsStyle.background(of: color(role), over: theme.panel.background).hexString
    }

    /// No prompt escape with braces goes inside `${name:+…}`: zsh would end the word at the escape's `}` (block 2
    /// review, C1). Colors sit outside the condition; with an empty value they paint nothing.
    func paint(_ part: ImmediatePart, gap: String) -> String {
        switch part {
        case .variable(let name, let icon, let role):
            return gap + pill(role, iconPrefix(icon, role) + foreground(role, "${\(name)}"), pad: " ")
        case .optional(let name, let role):
            let pad = "${\(name):+ }"
            return "${\(name):+\(gap)}" + pill(role, foreground(role, "${\(name)}"), pad: pad)
        case .clock(let icon, let role):
            return gap + pill(role, iconPrefix(icon, role) + foreground(role, "%D{%H:%M}"), pad: " ")
        }
    }

    private func pill(_ role: SegmentColor, _ body: String, pad: String) -> String {
        guard isPills else { return body }
        return "%K{\(background(role))}\(pad)\(body)\(pad)%k"
    }

    private func iconPrefix(_ icon: PromptIcon?, _ role: SegmentColor) -> String {
        guard let character = icon.flatMap(icons.character(for:)) else { return "" }
        return foreground(role, String(character)) + " "
    }

    /// Accent after success, error red after a failure, then `exit N` in secondary: zsh decides with `%(?..)`.
    func conditionalSymbol() -> String {
        let ok = color(.accent).hexString
        let failed = color(.failed).hexString
        let secondary = color(.secondary).hexString
        return "%(?.%F{\(ok)}.%F{\(failed)})${\(ZshPromptRenderer.symbolVariable)}%f%(?.. %F{\(secondary)}exit %?%f) "
    }
}
