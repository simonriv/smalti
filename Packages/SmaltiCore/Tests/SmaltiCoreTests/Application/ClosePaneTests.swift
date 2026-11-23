import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("ClosePane")
struct ClosePaneTests {
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

    @Test mutating func closeRemovesPaneAndClosesEngine() throws {
        let pane = try openPane()

        let outcome = ClosePane(engine: engine).execute(pane, in: &set)

        #expect(outcome == .closed)
        #expect(set.workspace(containing: pane) == nil)
        #expect(engine.closedPanes == [pane])
    }

    @Test mutating func closingTwiceClosesEngineOnce() throws {
        let pane = try openPane()
        let close = ClosePane(engine: engine)

        _ = close.execute(pane, in: &set)
        let second = close.execute(pane, in: &set)

        #expect(second == .alreadyClosed)
        #expect(engine.closedPanes == [pane])
    }

    @Test mutating func closingLastPaneKeepsEmptyWorkspace() throws {
        let pane = try openPane()

        _ = ClosePane(engine: engine).execute(pane, in: &set)

        #expect(set.workspaces.count == 1)
        #expect(set.active.panes.isEmpty)
    }

    @Test mutating func closeFindsPaneInHiddenWorkspace() throws {
        let hiddenPane = try openPane()
        let hiddenID = set.activeID
        let other = Workspace.empty(name: "other", rootDirectory: set.active.rootDirectory, layout: DwindleLayout())
        set = set.adding(other)

        let outcome = ClosePane(engine: engine).execute(hiddenPane, in: &set)

        #expect(outcome == .closed)
        #expect(set.workspaces.first { $0.id == hiddenID }?.panes.isEmpty == true)
        #expect(set.activeID == other.id)
    }
}
