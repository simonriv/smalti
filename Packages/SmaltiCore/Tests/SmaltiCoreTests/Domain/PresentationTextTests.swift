import SmaltiCore
import Testing

@Suite("Presentation text")
struct PresentationTextTests {
    private let home = Self.simonHome

    // Safe: a literal absolute path always parses.
    private static let simonHome = try! WorkingDirectory(path: "/Users/simon")

    private func workspace(panes count: Int) throws -> Workspace {
        let root = try WorkingDirectory(path: "/Users/simon/dev/solen")
        var workspace = Workspace.empty(name: "solen", rootDirectory: root, layout: DwindleLayout())
        for _ in 0..<count { workspace = workspace.adding(Pane(id: PaneID(), workingDirectory: root)) }
        return workspace
    }

    @Test func statusLineMatchesTheBoard() throws {
        #expect(try workspace(panes: 3).statusLine == "solen · 3 paneles · dwindle")
    }

    @Test func statusLineUsesSingularForOnePane() throws {
        #expect(try workspace(panes: 1).statusLine == "solen · 1 panel · dwindle")
    }

    @Test func statusLineForEmptyWorkspace() throws {
        #expect(try workspace(panes: 0).statusLine == "solen · 0 paneles · dwindle")
    }

    @Test func headerShowsProcessDirectoryAndShortcut() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/simon/dev/xolken"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "claude")))

        let header = PaneHeaderContent(pane, index: 3, keymap: .standard, home: home)

        #expect(header == PaneHeaderContent(process: "claude", directory: "~/dev/xolken", shortcut: "⌘3"))
    }

    @Test func headerWithoutIndexHasNoShortcut() throws {
        let pane = Pane(id: PaneID(), workingDirectory: home).applying(.titleChanged("vim notes.md"))

        let header = PaneHeaderContent(pane, index: nil, keymap: .standard, home: home)

        #expect(header == PaneHeaderContent(process: "vim notes.md", directory: "~", shortcut: ""))
    }
}
