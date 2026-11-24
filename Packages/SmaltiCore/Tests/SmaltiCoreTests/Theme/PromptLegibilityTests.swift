import Foundation
import SmaltiCore
import Testing

/// Final review (I4): with "Proteger legibilidad" every piece of the prompt reaches 4.5:1 over what it sits on: the
/// protected panel over the theme's worst desktop, or its own pill.
@Suite("Prompt legibility")
struct PromptLegibilityTests {
    private static let minimum = 4.5

    /// Everything that paints text in a color of its own: an error, a waiting and a failed agent, git, a runtime.
    private var context: PromptContext {
        var context = PromptContext(directory: "/Users/you/dev/solen/apps/api", home: "/Users/you")
        context.repoRoot = "/Users/you/dev/solen"
        context.branch = "main"
        context.changes = GitChanges(modified: 2, staged: 1)
        context.runtime = RuntimeVersion(kind: .node, version: "22.11")
        context.lastExit = 1
        context.agents = WaitingAgents(waiting: ["claude"], failed: ["codex"])
        return context
    }

    private func config(_ style: PromptStyleID) -> PromptConfig {
        var config = PromptConfig.standard
        config.style = style
        config.layout = .oneLine
        return config
    }

    @Test(arguments: ThemeID.allCases, [PromptStyleID.clean, .pills])
    func everyPieceReaches4_5(_ id: ThemeID, _ style: PromptStyleID) {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = id
        let theme = ThemeCatalog.apply(appearance).theme
        let ground = id.worstBackdrop.color.underneath(theme.window.background).underneath(theme.panel.background)

        let runs = PromptPreview.lines(config(style), context: context, theme: theme).flatMap { $0 }
            .filter { !$0.text.allSatisfy(\.isWhitespace) }

        let low = runs.filter { ContrastRatio.between($0.color, $0.background ?? ground) < Self.minimum }
        #expect(low.isEmpty, "\(id) \(style): \(low.map { "\($0.text) \($0.color.hexString)" })")
    }
}
