import SmaltiCore
import Testing

@Suite("ProcessesTokens")
struct ProcessesTokensTests {
    private let theme = Theme.obsidian

    @Test func stateCodeMatchesTheRestOfTheApp() {
        #expect(theme.statusDot(for: ProcessState.active) == .filled(theme.agent.working))
        #expect(theme.statusDot(for: ProcessState.unresponsive) == .filled(theme.agent.waiting))
        #expect(theme.statusDot(for: ProcessState.zombie) == .filled(theme.agent.failed))
        #expect(
            theme.statusDot(for: ProcessState.idle) == .hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth)
        )
        #expect(theme.statusDot(for: ProcessState.stopped) == theme.statusDot(for: ProcessState.idle))
    }

    @Test func quietStatesUseSecondaryText() {
        #expect(theme.stateTextColor(for: .idle) == theme.text.secondary)
        #expect(theme.stateTextColor(for: .active) == theme.agent.working)
        #expect(theme.stateTextColor(for: .unresponsive) == theme.agent.waiting)
        #expect(theme.stateTextColor(for: .zombie) == theme.agent.failed)
    }

    @Test func columnsOfTheMockup() {
        #expect(theme.processes.processColumns.count == 6)
        #expect(theme.processes.portColumns.count == 7)
        #expect(theme.processes.rowHeight == 36)
    }

    @Test(arguments: ThemeID.allCases)
    func everyThemeKeepsTheAccentForPanesMemory(id: ThemeID) {
        let theme = ThemeCatalog.theme(id)

        #expect(theme.processes.panesMemory == theme.accent)
    }
}
