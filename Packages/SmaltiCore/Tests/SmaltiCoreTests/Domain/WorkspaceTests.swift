import SmaltiCore
import Testing

@Suite("Workspace")
struct WorkspaceTests {
    private let root: WorkingDirectory
    private let geometry = LayoutGeometry.standard(area: Rect(x: 10, y: 10, width: 1308, height: 732))

    init() throws {
        root = try WorkingDirectory(path: "/Users/s")
    }

    private func makeWorkspace(_ layout: any LayoutStrategy = DwindleLayout()) -> Workspace {
        Workspace.empty(name: "main", rootDirectory: root, layout: layout)
    }

    private func makePane() -> Pane {
        Pane(id: PaneID(), workingDirectory: root)
    }

    private func filled(_ count: Int) -> (Workspace, [Pane]) {
        let panes = (0..<count).map { _ in makePane() }
        return (panes.reduce(makeWorkspace()) { $0.adding($1) }, panes)
    }

    @Test func addingFocusesNewPaneAndRebuildsTree() {
        let (workspace, panes) = filled(2)

        #expect(workspace.panes.map(\.id) == panes.map(\.id))
        #expect(workspace.focusedPane == panes[1].id)
        #expect(workspace.tree?.panes == panes.map(\.id))
    }

    @Test func removingFocusedPaneFocusesPrevious() {
        let (workspace, panes) = filled(3)

        let result = workspace.removing(panes[2].id)

        #expect(result.focusedPane == panes[1].id)
        #expect(result.tree?.panes == [panes[0].id, panes[1].id])
    }

    @Test func removingFirstFocusesNext() {
        let (workspace, panes) = filled(3)

        let result = workspace.focusing(panes[0].id).removing(panes[0].id)

        #expect(result.focusedPane == panes[1].id)
    }

    @Test func removingLastLeavesEmptyWorkspaceWithoutFocus() {
        let (workspace, panes) = filled(1)

        let result = workspace.removing(panes[0].id)

        #expect(result.panes.isEmpty)
        #expect(result.focusedPane == nil)
        #expect(result.tree == nil)
    }

    @Test func structuralChangeDropsManualRatios() {
        let (workspace, panes) = filled(2)
        let resized = workspace.resizing(
            ResizeRequest(pane: panes[0].id, direction: .right, step: 0.05), within: geometry)
        #expect(resized.tree != workspace.tree)

        let grown = resized.adding(makePane())

        #expect(grown.tree == DwindleLayout().tree(for: grown.panes.map(\.id)))
    }

    @Test func swapKeepsManualRatios() {
        let (workspace, panes) = filled(2)
        let resized = workspace.resizing(
            ResizeRequest(pane: panes[0].id, direction: .right, step: 0.05), within: geometry)

        let swapped = resized.swapping(panes[0].id, panes[1].id)

        #expect(swapped.panes.map(\.id) == [panes[1].id, panes[0].id])
        #expect(swapped.tree == resized.tree?.swapping(panes[0].id, panes[1].id))
    }

    @Test func newPaneUsesFocusedPaneDirectory() throws {
        let (workspace, panes) = filled(2)
        let elsewhere = try WorkingDirectory(path: "/tmp")

        let moved = workspace.applying(.workingDirectoryChanged(elsewhere), to: panes[1].id)

        #expect(moved.directoryForNewPane == elsewhere)
    }

    @Test func newPaneFallsBackToRootDirectory() {
        #expect(makeWorkspace().directoryForNewPane == root)
    }

    @Test func unknownPaneIsIgnored() {
        let (workspace, _) = filled(2)
        let stranger = PaneID()

        #expect(workspace.removing(stranger) == workspace)
        #expect(workspace.focusing(stranger) == workspace)
        #expect(workspace.swapping(stranger, workspace.panes[0].id) == workspace)
        #expect(workspace.applying(.bell, to: stranger) == workspace)
        #expect(!workspace.contains(stranger))
        #expect(workspace.index(of: stranger) == nil)
    }

    @Test func indexIsOneBased() {
        let (workspace, panes) = filled(3)

        #expect(workspace.index(of: panes[0].id) == 1)
        #expect(workspace.index(of: panes[2].id) == 3)
    }

    @Test func switchingLayoutRebuildsTree() {
        let (workspace, panes) = filled(3)

        let result = workspace.switchingLayout(to: ColumnsLayout())

        #expect(result.layout.id == .columns)
        #expect(result.tree == ColumnsLayout().tree(for: panes.map(\.id)))
    }

    @Test func equalizedResetsRatios() {
        let (workspace, panes) = filled(3)
        let resized = workspace.resizing(
            ResizeRequest(pane: panes[0].id, direction: .right, step: 0.05), within: geometry)

        #expect(resized.equalized().tree == workspace.tree?.equalized())
    }

    @Test func renamedChangesOnlyTheName() {
        let (workspace, _) = filled(2)

        let result = workspace.renamed("api")

        #expect(result.name == "api")
        #expect(result.panes == workspace.panes)
    }

    @Test func equalityComparesLayoutById() {
        let (workspace, _) = filled(2)

        #expect(workspace.switchingLayout(to: ColumnsLayout()) != workspace)
        #expect(workspace.switchingLayout(to: DwindleLayout()) == workspace)
    }

    @Test func equalityDetectsRenamedWorkspaceWithSameTree() {
        let workspace = makeWorkspace()

        #expect(workspace.renamed("other") != workspace)
    }
}
