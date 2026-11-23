import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("HandlePaneExit")
struct HandlePaneExitTests {
    private let engine = FakeTerminalEngine()
    private let geometry = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 1000, height: 600))
    private var set: WorkspaceSet

    init() throws {
        let root = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
    }

    private mutating func openPane() throws -> PaneID {
        try OpenPane(engine: engine, version: "1")
            .execute(OpenPaneRequest(shell: .loginShell, geometry: geometry), in: &set)
    }

    private func exit(_ pane: PaneID, code: Int? = 0, after lifetime: Duration) -> PaneExit {
        PaneExit(pane: pane, exitCode: code, lifetime: lifetime)
    }

    @Test mutating func healthyExitClosesPane() throws {
        let pane = try openPane()

        let outcome = HandlePaneExit(engine: engine).execute(exit(pane, after: .seconds(5)), in: &set)

        #expect(outcome == .closed)
        #expect(set.workspace(containing: pane) == nil)
        #expect(engine.closedPanes == [pane])
    }

    @Test mutating func exitRightAfterStartIsReported() throws {
        let pane = try openPane()

        let outcome = HandlePaneExit(engine: engine)
            .execute(exit(pane, code: 127, after: .milliseconds(80)), in: &set)

        #expect(outcome == .closedAfterFailedStart(exitCode: 127))
        #expect(set.workspace(containing: pane) == nil)
    }

    @Test mutating func exactlyMinimumLifetimeIsHealthy() throws {
        let pane = try openPane()

        let outcome = HandlePaneExit(engine: engine)
            .execute(exit(pane, after: HandlePaneExit.minimumHealthyLifetime), in: &set)

        #expect(outcome == .closed)
    }

    @Test mutating func exitOfAlreadyClosedPaneIsIgnored() throws {
        let pane = try openPane()
        let handle = HandlePaneExit(engine: engine)
        _ = handle.execute(exit(pane, after: .seconds(5)), in: &set)

        let outcome = handle.execute(exit(pane, code: 1, after: .zero), in: &set)

        #expect(outcome == .alreadyClosed)
        #expect(engine.closedPanes == [pane])
    }

    @Test mutating func exitInHiddenWorkspaceLeavesActiveUntouched() throws {
        let hiddenPane = try openPane()
        set = set.adding(
            .empty(name: "other", rootDirectory: set.active.rootDirectory, layout: DwindleLayout()))
        let activeBefore = set.active

        let outcome = HandlePaneExit(engine: engine).execute(exit(hiddenPane, after: .seconds(5)), in: &set)

        #expect(outcome == .closed)
        #expect(set.active == activeBefore)
        #expect(set.workspace(containing: hiddenPane) == nil)
    }
}
