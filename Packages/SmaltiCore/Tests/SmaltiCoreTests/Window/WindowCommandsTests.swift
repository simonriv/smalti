import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("WindowCommands")
struct WindowCommandsTests {
    private let engine = FakeTerminalEngine()
    private let roomy = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 1000, height: 600))
    private let root: WorkingDirectory
    private let other: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
        other = try WorkingDirectory(path: "/tmp/other")
    }

    private func request() -> CreateWorkspaceRequest {
        CreateWorkspaceRequest(pane: OpenPaneRequest(shell: .loginShell, geometry: roomy), layout: DwindleLayout())
    }

    private func firstWindow() throws -> WindowSet {
        var set: WindowSet?
        let id = try OpenWindow(engine: engine, version: "1").execute(request(), in: root, into: &set)
        _ = id
        return try #require(set)
    }

    @Test func openWindowStartsOnePaneInDirectory() throws {
        var set = try firstWindow()

        let id = try OpenWindow(engine: engine, version: "1").execute(request(), in: other, into: &set)

        #expect(set.frontID == id)
        #expect(set.front.workspaces.active.panes.count == 1)
        #expect(set.front.workspaces.active.name == "other")
        #expect(engine.openedSpecs.last?.workingDirectory == other)
    }

    @Test func openWindowFailureLeavesTheSetUntouched() throws {
        var set = try firstWindow()
        let before = set
        engine.failure = .surfaceCreationFailed(workingDirectory: "/tmp/other", reason: "test")

        #expect(throws: OpenPaneError.self) {
            try OpenWindow(engine: engine, version: "1").execute(request(), in: other, into: &set)
        }
        #expect(set == before)
    }

    @Test func closeWindowClosesItsPanesInEngine() throws {
        var set = try firstWindow()
        let second = try OpenWindow(engine: engine, version: "1").execute(request(), in: other, into: &set)
        let panes = set.front.workspaces.active.panes.map(\.id)

        let outcome = CloseWindow(engine: engine).execute(second, in: &set)

        #expect(outcome == .closed)
        #expect(engine.closedPanes == panes)
        #expect(set.windows.count == 1)
    }

    @Test func closeLastWindowReportsIsLastAndClosesNothing() throws {
        var set = try firstWindow()

        let outcome = CloseWindow(engine: engine).execute(set.frontID, in: &set)

        #expect(outcome == .isLast)
        #expect(engine.closedPanes.isEmpty)
        #expect(set.windows.count == 1)
    }
}
