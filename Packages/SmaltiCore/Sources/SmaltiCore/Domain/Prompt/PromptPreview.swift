/// One piece of a previewed prompt line with its colors already resolved, as the studio paints it (spec F5).
public struct PreviewRun: Equatable, Sendable {
    public let text: String
    public let color: RGBAColor
    public let background: RGBAColor?
}

/// The board's three situations ("Carpeta normal", "Proyecto Node con git", "Después de un error, con agente activo").
public enum PreviewSituation: CaseIterable, Sendable {
    case normalFolder
    case nodeProject
    case afterErrorWithAgent

    private static let home = "/Users/you"

    var context: PromptContext {
        switch self {
        case .normalFolder:
            return PromptContext(directory: Self.home + "/Downloads", home: Self.home)
        case .nodeProject:
            var context = PromptContext(directory: Self.home + "/dev/solen/apps/api", home: Self.home)
            context.repoRoot = Self.home + "/dev/solen"
            context.branch = "feat/reminders"
            context.changes = GitChanges(modified: 2, staged: 1)
            context.runtime = RuntimeVersion(kind: .node, version: "22.11")
            return context
        case .afterErrorWithAgent:
            var context = PromptContext(directory: Self.home + "/dev/rizaria/web", home: Self.home)
            context.branch = "main"
            context.duration = .milliseconds(4200)
            context.agents = WaitingAgents(waiting: ["claude"])
            context.lastExit = 1
            return context
        }
    }
}

public enum PromptPreview {
    public static func lines(_ config: PromptConfig, context: PromptContext, theme: Theme) -> [[PreviewRun]] {
        let style = PromptStyles.style(for: config.style)
        let symbol = SymbolSegment(symbol: config.symbol, lastExit: context.lastExit)
        let lines = style.lines(PromptModules.segments(for: config, in: context), symbol: symbol, layout: config.layout)
        return lines.map {
            drawableRuns($0, icons: config.icons).map { run(of: $0, icons: config.icons, theme: theme) }
        }
    }

    private static func run(of styled: StyledRun, icons: PromptIcons, theme: Theme) -> PreviewRun {
        let text: String
        switch styled.content {
        case .text(let value): text = value
        case .icon(let icon): text = icons.character(for: icon).map(String.init) ?? ""
        case .symbol(let symbol): text = symbol.rawValue
        }
        let background = styled.background.map {
            PillsStyle.background(of: theme.color(for: $0), over: theme.panel.background)
        }
        return PreviewRun(text: text, color: theme.color(for: styled.color), background: background)
    }
}
