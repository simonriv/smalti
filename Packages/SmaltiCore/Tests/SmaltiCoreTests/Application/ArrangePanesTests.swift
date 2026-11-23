import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("ArrangePanes")
struct ArrangePanesTests {
    private let geometry = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 1000, height: 600))
    private let ids = [PaneID(), PaneID()]
    private var set: WorkspaceSet

    init() throws {
        let root = try WorkingDirectory(path: "/tmp")
        var workspace = Workspace.empty(name: "tmp", rootDirectory: root, layout: ColumnsLayout())
        for id in ids { workspace = workspace.adding(Pane(id: id, workingDirectory: root)) }
        set = WorkspaceSet(first: workspace)
    }

    @Test mutating func focusByDirectionMovesToNeighbor() {
        set = set.updating(set.activeID) { $0.focusing(ids[0]) }

        FocusPane().execute(.direction(.right), geometry: geometry, in: &set)

        #expect(set.active.focusedPane == ids[1])
    }

    @Test mutating func focusWithoutNeighborDoesNothing() {
        let before = set

        FocusPane().execute(.direction(.right), geometry: geometry, in: &set)

        #expect(set == before)
    }

    @Test mutating func focusByIndexIsOneBased() {
        FocusPane().execute(.index(1), geometry: geometry, in: &set)

        #expect(set.active.focusedPane == ids[0])
    }

    @Test mutating func focusByIndexOutOfRangeDoesNothing() {
        let before = set

        FocusPane().execute(.index(0), geometry: geometry, in: &set)
        FocusPane().execute(.index(3), geometry: geometry, in: &set)

        #expect(set == before)
    }

    @Test mutating func swapWithRightNeighbor() {
        set = set.updating(set.activeID) { $0.focusing(ids[0]) }

        SwapPane().execute(toward: .right, geometry: geometry, in: &set)

        #expect(set.active.panes.map(\.id) == [ids[1], ids[0]])
        #expect(set.active.focusedPane == ids[0])
    }

    @Test mutating func swapWithoutNeighborDoesNothing() {
        let before = set

        SwapPane().execute(toward: .right, geometry: geometry, in: &set)

        #expect(set == before)
    }

    @Test mutating func resizeStepsFivePercent() {
        set = set.updating(set.activeID) { $0.focusing(ids[0]) }

        ResizePane().execute(toward: .right, geometry: geometry, in: &set)

        guard case .split(_, let ratio, _, _) = set.active.tree else {
            Issue.record("expected a split")
            return
        }
        #expect(abs(ratio.value - 0.55) < 1e-9)
    }

    @Test mutating func resizeWithoutFocusDoesNothing() throws {
        let root = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: ColumnsLayout()))
        let before = set

        ResizePane().execute(toward: .right, geometry: geometry, in: &set)

        #expect(set == before)
    }

    @Test mutating func equalizeRestoresEvenSplits() {
        let even = set.active.tree
        set = set.updating(set.activeID) { $0.focusing(ids[0]) }
        ResizePane().execute(toward: .right, geometry: geometry, in: &set)

        EqualizePanes().execute(in: &set)

        #expect(set.active.tree == even)
    }

    @Test mutating func switchLayoutRebuildsTree() {
        SwitchLayout().execute(to: DwindleLayout(), in: &set)

        #expect(set.active.layout.id == .dwindle)
        #expect(set.active.tree == DwindleLayout().tree(for: ids))
    }
}
