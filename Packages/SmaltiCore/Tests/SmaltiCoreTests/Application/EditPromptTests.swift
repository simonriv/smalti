import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5, "Estudio de prompt": a draft previewed in the board's three situations, applied on demand.
@MainActor
@Suite("EditPrompt")
struct EditPromptTests {
    private let store = InMemoryAppearanceStore()
    private let debouncer = ManualDebouncer()

    private func make() -> (EditPrompt, ChangeAppearance) {
        var config = SmaltiConfig.defaults
        config.appearance.protectLegibility = false
        let appearance = ChangeAppearance(
            document: AppearanceDocument(config: config), store: store, debouncer: debouncer)
        return (EditPrompt(appearance: appearance), appearance)
    }

    private func text(_ lines: [[PreviewRun]]) -> [String] {
        lines.map { $0.map(\.text).joined() }
    }

    @Test func previewSituationsMatchBoard() {
        let (edit, _) = make()

        #expect(text(edit.preview(.normalFolder)) == ["\u{E900} ~/Downloads", "› "])
        #expect(
            text(edit.preview(.nodeProject)) == [
                "\u{E900} solen/apps/api   \u{E901} feat/reminders ●2 +1   \u{E902} 22.11", "› ",
            ])
        #expect(
            text(edit.preview(.afterErrorWithAgent)) == [
                "\u{E900} rizaria/web   \u{E901} main   4.2s   ● claude te espera", "› exit 1 ",
            ])
    }

    @Test func previewUsesThemeColors() throws {
        let (edit, _) = make()

        let first = try #require(edit.preview(.normalFolder).first?.first)

        #expect(first.color == (try RGBAColor(hex: "#7aa2f7")))
        #expect(first.background == nil)
    }

    @Test func previewFollowsTheDraft() {
        let (edit, _) = make()

        edit.draft = edit.draft.applying(.symbolOnly)

        #expect(text(edit.preview(.nodeProject)) == ["› "])
    }

    @Test func draftDoesNotTouchLivePromptUntilApply() {
        let (edit, appearance) = make()

        edit.draft.symbol = .lambda

        #expect(appearance.document.prompt.symbol == .chevron)
        #expect(store.saved.isEmpty)
    }

    @Test func applySavesAtOnce() {
        let (edit, appearance) = make()
        edit.draft.symbol = .lambda

        edit.apply()

        #expect(appearance.document.prompt.symbol == .lambda)
        #expect(store.saved.last?.prompt.symbol == .lambda)
    }

    @Test func moveModuleUpAndDown() {
        let (edit, _) = make()

        edit.move(.gitBranch, by: -1)
        #expect(Array(edit.draft.modules.prefix(2)) == [.gitBranch, .directory])

        edit.move(.gitBranch, by: 1)
        #expect(Array(edit.draft.modules.prefix(2)) == [.directory, .gitBranch])
    }

    /// Block 5 review (I2): a drag over several rows moves the module, the others keep their order.
    @Test func moveSeveralPlacesShiftsTheOthers() {
        let (edit, _) = make()

        edit.move(.directory, by: 3)

        #expect(edit.draft.modules == [.gitBranch, .gitStatus, .runtime, .directory, .duration, .agents])
    }

    @Test func moveBeyondTheEndStopsAtTheEdge() {
        let (edit, _) = make()

        edit.move(.gitStatus, by: 10)

        #expect(edit.draft.modules.last == .gitStatus)
        #expect(edit.draft.modules.count == 6)
    }

    @Test func moveFirstUpIsNoop() {
        let (edit, _) = make()
        let before = edit.draft.modules

        edit.move(.directory, by: -1)

        #expect(edit.draft.modules == before)
    }

    @Test func moveLastDownIsNoop() {
        let (edit, _) = make()
        let before = edit.draft.modules

        edit.move(.agents, by: 1)

        #expect(edit.draft.modules == before)
    }

    @Test func toggleOffRemovesAndOnAppends() {
        let (edit, _) = make()

        edit.toggle(.gitBranch)
        #expect(!edit.draft.modules.contains(.gitBranch))

        edit.toggle(.time)
        #expect(edit.draft.modules.last == .time)
    }

    @Test func moduleListShowsActiveThenInactive() {
        let (edit, _) = make()

        #expect(edit.moduleList.map(\.id) == PromptModuleID.allCases)
        #expect(edit.moduleList.filter(\.isActive).map(\.id) == PromptConfig.standard.modules)
    }
}
