import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("FakeTerminalEngine · F4.5")
struct FakeTerminalEngineActionsTests {
    @Test func fakeMeetsTheActionsContract() throws {
        try TerminalEngineActionsContract.verify { FakeTerminalEngine() }
    }

    @Test func fakeRecordsActionsPerPane() throws {
        let engine = FakeTerminalEngine()
        let pane = PaneID()
        try engine.open(.loginShell(in: WorkingDirectory(path: "/tmp")), as: pane)

        engine.perform(.scroll(.top), in: pane)
        engine.search("warn", in: pane)
        engine.navigateSearch(.next, in: pane)
        engine.endSearch(in: pane)

        #expect(engine.performed == [.init(action: .scroll(.top), pane: pane)])
        #expect(engine.searches == [.init(text: "warn", pane: pane)])
        #expect(engine.searchNavigations == [.init(direction: .next, pane: pane)])
        #expect(engine.endedSearches == [pane])
    }

    @Test func fakeReportsTheVisibleTextItWasGiven() throws {
        let engine = FakeTerminalEngine()
        let pane = PaneID()
        try engine.open(.loginShell(in: WorkingDirectory(path: "/tmp")), as: pane)
        engine.visibleTexts[pane] = "hola"

        #expect(engine.visibleText(of: pane) == "hola")
    }
}
