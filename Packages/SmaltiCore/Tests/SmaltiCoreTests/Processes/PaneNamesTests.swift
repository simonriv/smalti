import SmaltiCore
import Testing

@Suite("PaneNames")
struct PaneNamesTests {
    private func pane() throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
    }

    private func window(_ name: String, _ panes: [Pane]) throws -> WindowState {
        let root = try WorkingDirectory(path: "/tmp")
        let workspace = panes.reduce(Workspace.empty(name: name, rootDirectory: root, layout: DwindleLayout())) {
            $0.adding($1)
        }
        return WindowState(id: WindowID(), workspaces: WorkspaceSet(first: workspace), frame: nil, isFullScreen: false)
    }

    @Test func workspaceAndNumberInEveryWindow() throws {
        let first = try pane()
        let second = try pane()
        let other = try pane()
        let windows = WindowSet(first: try window("web", [first, second])).opening(try window("api", [other]))

        let names = PaneNames.of(windows, texts: .spanish)

        #expect(names[first.id] == "web · 1")
        #expect(names[second.id] == "web · 2")
        #expect(names[other.id] == "api · 1")
    }
}
