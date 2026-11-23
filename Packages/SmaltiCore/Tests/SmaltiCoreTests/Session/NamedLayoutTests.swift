import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Named layouts")
struct NamedLayoutTests {
    private let engine = FakeTerminalEngine()
    private let layouts = InMemoryNamedLayouts()
    private let archive = InMemorySessionArchive()
    private let home = SessionFixtures.directory("/Users/s")
    private let root = SessionFixtures.directory("/Users/s/dev/solen")

    private var restore: RestoreSession {
        RestoreSession(
            .init(
                engine: engine, transcripts: archive, harnesses: HarnessRegistry([FakeHarnessAdapter()]),
                environment: PaneEnvironment(version: "2"), shell: .loginShell, clock: { SessionFixtures.now }))
    }

    private func agentPane(_ sessionID: String) -> Pane {
        Pane(id: PaneID(), workingDirectory: root).attaching(
            AgentSession(
                harness: .claude, sessionID: sessionID, title: nil, state: .working, startedAt: SessionFixtures.now))
    }

    private func saved(_ panes: [Pane]) throws -> LayoutName {
        let workspace = panes.reduce(Workspace.empty(name: "solen", rootDirectory: root, layout: ColumnsLayout())) {
            $0.adding($1)
        }
        let name = try LayoutName("solen-dev")
        try SaveNamedLayout(layouts: layouts).execute(workspace, as: name)
        return name
    }

    private func existingSet() -> WorkspaceSet {
        WorkspaceSet(first: Workspace.empty(name: "home", rootDirectory: home, layout: DwindleLayout()))
    }

    @Test func namedLayoutOpensNewWorkspaceWithItsName() throws {
        let name = try saved([Pane(id: PaneID(), workingDirectory: root)])
        var set = existingSet()

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(set.workspaces.map(\.name) == ["home", "solen-dev"])
        #expect(set.active.name == "solen-dev")
        #expect(set.active.layout.id == .columns)
    }

    @Test func namedLayoutRunsSavedCommands() throws {
        let server = Pane(id: PaneID(), workingDirectory: root)
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "node", commandLine: ["pnpm", "dev"])))
        let name = try saved([server])
        var set = existingSet()

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(engine.openedSpecs[0].initialInput == "pnpm dev\n")
        #expect(engine.openedSpecs[0].restoration?.scrollback == nil)
    }

    @Test func namedLayoutResumesAgents() throws {
        let name = try saved([agentPane("7f3a")])
        var set = existingSet()

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(engine.openedSpecs[0].initialInput == "fake --resume 7f3a\n")
    }

    @Test func namedLayoutSkipsSessionAlreadyLive() throws {
        let name = try saved([agentPane("7f3a")])
        var set = existingSet()
        set = set.updating(set.activeID) { $0.adding(agentPane("7f3a")) }

        let outcome = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(engine.openedSpecs[0].initialInput == nil)
        #expect(outcome.skippedLiveSessions == ["7f3a"])
    }

    @Test func restoredLayoutGetsFreshPaneIdentities() throws {
        let original = Pane(id: PaneID(), workingDirectory: root)
        let name = try saved([original])
        var set = existingSet()

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(set.active.panes.first?.id != original.id)
    }

    @Test func missingLayoutThrows() throws {
        var set = existingSet()

        #expect(throws: SessionArchiveError.self) {
            try RestoreNamedLayout(layouts: layouts, restore: restore).execute(
                try LayoutName("nada"), into: &set, home: home)
        }
    }

    @Test func previousWorkspacePanesAreHidden() throws {
        let name = try saved([Pane(id: PaneID(), workingDirectory: root)])
        let visible = Pane(id: PaneID(), workingDirectory: home)
        var set = existingSet()
        set = set.updating(set.activeID) { $0.adding(visible) }

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        #expect(engine.hiddenPanes == [visible.id])
    }

    @Test func failedPaneInANamedLayoutRebuildsTheTree() throws {
        let first = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp/ok"))
        let lost = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp/borrada"))
        let name = try saved([first, lost])
        engine.failingDirectories = ["/tmp/borrada", "/Users/s/dev/solen", "/Users/s"]
        var set = existingSet()

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(name, into: &set, home: home)

        let ids = set.active.panes.map(\.id)
        #expect(ids.count == 1)
        #expect(set.active.tree == ColumnsLayout().tree(for: ids))
    }
}
