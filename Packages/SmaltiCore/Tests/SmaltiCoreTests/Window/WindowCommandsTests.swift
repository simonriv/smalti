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

    private func window(in directory: WorkingDirectory) throws -> WindowState {
        var workspaces = WorkspaceSet(
            first: .empty(name: directory.lastComponent, rootDirectory: directory, layout: DwindleLayout()))
        _ = try OpenPane(engine: engine, version: "1").execute(
            OpenPaneRequest(shell: .loginShell, geometry: roomy), in: &workspaces)
        return WindowState(id: WindowID(), workspaces: workspaces, frame: nil, isFullScreen: false)
    }

    private func firstWindow() throws -> WindowSet {
        WindowSet(first: try window(in: root))
    }

    @Test func closeWindowClosesItsPanesInEngine() throws {
        let other = try window(in: other)
        var set = try firstWindow().opening(other)
        let second = other.id
        let panes = other.workspaces.active.panes.map(\.id)

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
