import SmaltiCore
import Testing

@Suite("TimelineTokens")
struct TimelineTokensTests {
    private let theme = Theme.obsidian

    @Test func measuresOfTheMockup() {
        #expect(theme.timeline.width == 480)
        #expect(theme.timeline.margin == 10)
        #expect(theme.timeline.radius == 12)
        #expect(theme.timeline.headerHeight == theme.chrome.topStripHeight)
        #expect(theme.timeline.footerHeight == 30)
        #expect(theme.timeline.toolRowHeight == 24)
        #expect(theme.timeline.childIndent == 18)
    }

    @Test func toolStatesUseTheAppStateCode() {
        #expect(theme.timeline.color(for: .done) == theme.agent.working)
        #expect(theme.timeline.color(for: .working) == theme.agent.working)
        #expect(theme.timeline.color(for: .failed(exitCode: 1)) == theme.agent.failed)
        #expect(theme.timeline.unidentifiedDot == theme.agent.waiting)
        #expect(theme.timeline.toolName == theme.terminal.palette[6])
    }

    @Test(arguments: ThemeID.allCases)
    func everyThemeMarksPromptsAndMatchesWithItsAccent(id: ThemeID) {
        let theme = ThemeCatalog.theme(id)

        #expect(theme.timeline.promptEdge == theme.accent.withAlpha(0.55))
        #expect(theme.timeline.matchHighlight == theme.accent.withAlpha(0.28))
    }
}
