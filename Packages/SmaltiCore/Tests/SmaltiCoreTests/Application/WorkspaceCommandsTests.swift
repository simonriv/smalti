import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("WorkspaceCommands")
struct WorkspaceCommandsTests {
    private let engine = FakeTerminalEngine()
    private let roomy = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 1000, height: 600))
    private let cramped = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 300, height: 150))
    private let root: WorkingDirectory
    private var set: WorkspaceSet

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
        set = WorkspaceSet(first: .empty(name: "project", rootDirectory: root, layout: DwindleLayout()))
    }

    private func create(_ geometry: LayoutGeometry) -> CreateWorkspaceRequest {
        CreateWorkspaceRequest(
            pane: OpenPaneRequest(shell: .loginShell, geometry: geometry), layout: ColumnsLayout())
    }

    private func creator() -> CreateWorkspace {
        CreateWorkspace(engine: engine, version: "1")
    }

    private mutating func openInActive() throws -> PaneID {
        try OpenPane(engine: engine, version: "1").execute(
            OpenPaneRequest(shell: .loginShell, geometry: roomy), in: &set)
    }

    @Test mutating func createWorkspaceOpensPaneAndHidesPrevious() throws {
        let previous = try openInActive()

        let id = try creator().execute(create(roomy), in: &set)

        #expect(set.activeID == id)
        #expect(set.workspaces.count == 2)
        #expect(set.active.panes.count == 1)
        #expect(set.active.layout.id == .columns)
        #expect(engine.hiddenPanes == [previous])
    }

    @Test mutating func createWorkspaceNamesAfterRootDirectory() throws {
        let elsewhere = try WorkingDirectory(path: "/var/logs")
        set = set.updating(set.activeID) { $0.adding(Pane(id: PaneID(), workingDirectory: elsewhere)) }

        _ = try creator().execute(create(roomy), in: &set)

        #expect(set.active.rootDirectory == elsewhere)
        #expect(set.active.name == "logs")
    }

    @Test mutating func createWorkspaceFailureLeavesSetUnchanged() throws {
        _ = try openInActive()
        let before = set
        engine.failure = .surfaceCreationFailed(workingDirectory: "/tmp", reason: .engine("x"))

        #expect(throws: OpenPaneError.self) {
            try creator().execute(create(roomy), in: &set)
        }

        #expect(set == before)
        #expect(engine.hiddenPanes.isEmpty)
    }

    @Test mutating func renameTrimsAndIgnoresBlank() {
        RenameWorkspace().execute("  api  ", in: &set)
        #expect(set.active.name == "api")

        RenameWorkspace().execute(" \n\t ", in: &set)
        #expect(set.active.name == "api")
    }

    @Test mutating func switchHidesOutgoingAndShowsIncoming() throws {
        let first = try openInActive()
        let firstWorkspace = set.activeID
        let second = try creator().execute(create(roomy), in: &set)
        let secondPane = set.active.panes[0].id
        let switchWorkspace = SwitchWorkspace(engine: engine)

        switchWorkspace.execute(.id(firstWorkspace), in: &set)

        #expect(set.activeID == firstWorkspace)
        #expect(engine.hiddenPanes == [first, secondPane])
        #expect(engine.shownPanes == [first])

        switchWorkspace.execute(.index(2), in: &set)

        #expect(set.activeID == second)
        #expect(engine.hiddenPanes == [first, secondPane, first])
        #expect(engine.shownPanes == [first, secondPane])
    }

    @Test mutating func switchToActiveDoesNotHideOrShow() throws {
        _ = try openInActive()
        let switchWorkspace = SwitchWorkspace(engine: engine)

        switchWorkspace.execute(.id(set.activeID), in: &set)
        switchWorkspace.execute(.index(1), in: &set)
        switchWorkspace.execute(.index(5), in: &set)

        #expect(engine.hiddenPanes.isEmpty)
        #expect(engine.shownPanes.isEmpty)
    }

    @Test mutating func closeWorkspaceClosesItsPanes() throws {
        let first = try openInActive()
        let firstWorkspace = set.activeID
        let second = try creator().execute(create(roomy), in: &set)
        let secondPane = set.active.panes[0].id

        try CloseWorkspace(engine: engine).execute(second, in: &set)

        #expect(engine.closedPanes == [secondPane])
        #expect(set.activeID == firstWorkspace)
        #expect(engine.shownPanes == [first])
    }

    @Test mutating func closeInactiveWorkspaceShowsNothing() throws {
        let first = try openInActive()
        let firstWorkspace = set.activeID
        let second = try creator().execute(create(roomy), in: &set)

        try CloseWorkspace(engine: engine).execute(firstWorkspace, in: &set)

        #expect(engine.shownPanes.isEmpty)
        #expect(engine.closedPanes == [first])
        #expect(set.activeID == second)
    }

    @Test mutating func closeUnknownWorkspaceDoesNothing() throws {
        _ = try openInActive()
        _ = try creator().execute(create(roomy), in: &set)
        let before = set

        try CloseWorkspace(engine: engine).execute(WorkspaceID(), in: &set)

        #expect(set == before)
        #expect(engine.closedPanes.isEmpty)
        #expect(engine.shownPanes.isEmpty)
        #expect(engine.hiddenPanes.count == 1)
    }

    @Test mutating func closeLastWorkspaceThrows() throws {
        _ = try openInActive()
        let before = set

        #expect(throws: WorkspaceSetError.cannotCloseLastWorkspace) {
            try CloseWorkspace(engine: engine).execute(set.activeID, in: &set)
        }

        #expect(set == before)
        #expect(engine.closedPanes.isEmpty)
    }

    @Test mutating func closeWorkspaceReturnsTheClosedPanes() throws {
        _ = try openInActive()
        let second = try creator().execute(create(roomy), in: &set)
        let secondPane = try OpenPane(engine: engine, version: "1").execute(
            OpenPaneRequest(shell: .loginShell, geometry: roomy), in: &set)
        let expected = set.active.panes.map(\.id)

        let closed = try CloseWorkspace(engine: engine).execute(second, in: &set)

        #expect(closed == expected)
        #expect(closed.contains(secondPane))
    }

    @Test mutating func closeUnknownWorkspaceReturnsNoPanes() throws {
        _ = try openInActive()
        _ = try creator().execute(create(roomy), in: &set)

        let closed = try CloseWorkspace(engine: engine).execute(WorkspaceID(), in: &set)

        #expect(closed.isEmpty)
    }
}
