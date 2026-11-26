import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Pins behaviour that mutation testing showed no other test fixed.
@MainActor
@Suite("Edge cases found by mutation testing")
struct MutantKillerTests {
    private let engine = FakeTerminalEngine()
    private let archive = InMemorySessionArchive()

    // MARK: Paths with spaces ("Smalti Dev")

    @Test func paneEnvironmentKeepsSpacesInPaths() {
        let state = URL(filePath: "/Users/s/Library/Application Support/Smalti Dev")
        let ipc = IPCEndpoints(
            socket: state.appending(path: "smalti.sock"),
            cli: URL(filePath: "/Applications/Smalti Dev.app/Contents/Resources/bin/smalti"), inheritedPath: "/usr/bin")
        let pane = PaneID()

        let variables = PaneEnvironment(version: "1", files: PaneFileLocator(stateDirectory: state), ipc: ipc)
            .variables(for: pane)

        #expect(
            variables["SMALTI_HISTORY_FILE"]
                == "/Users/s/Library/Application Support/Smalti Dev/history/\(pane).zsh_history")
        #expect(variables["SMALTI_SOCKET"] == "/Users/s/Library/Application Support/Smalti Dev/smalti.sock")
        #expect(variables["SMALTI_CLI"] == "/Applications/Smalti Dev.app/Contents/Resources/bin/smalti")
        #expect(variables["PATH"] == "/Applications/Smalti Dev.app/Contents/Resources/bin:/usr/bin")
    }

    @Test func socketLengthCountsRealBytesNotEscapes() {
        // 100 bytes as written; with each space escaped as %20 (118) it would pass the 104-byte limit.
        let state = URL(
            filePath: "/Users/s/a b c d e f g h/Library/Application Support/Smalti Dev/xxxxxxxxxxxxxxxxxxxxxxxx")
        let socket = SocketLocation.socketFile(stateDirectory: state, temporaryDirectory: URL(filePath: "/var/t"))

        #expect(socket == state.appending(path: "smalti.sock"))
    }

    // MARK: Restoration

    private var restore: RestoreSession {
        RestoreSession(
            .init(
                engine: engine, transcripts: archive, harnesses: HarnessRegistry([FakeHarnessAdapter()]),
                environment: PaneEnvironment(version: "1"), shell: .loginShell, clock: { .now }, texts: .spanish))
    }

    private func plan(_ pane: PlannedPane) -> RestorePlan {
        RestorePlan(workspaces: [SessionFixtures.workspace("solen", [pane])], activeIndex: 0)
    }

    @Test func aPaneWithNothingToBringBackHasNoRestoration() {
        let clean = PlannedPane(
            id: UUID(), workingDirectory: "/tmp", restoresScrollback: false, restoresHistory: false, launch: .shell)

        _ = restore.execute(plan(clean), savedAt: .now, home: SessionFixtures.directory("/Users/s"))

        #expect(engine.openedSpecs.first?.restoration == nil)
    }

    @Test func historyAloneStillRestores() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        let historyOnly = PlannedPane(
            id: UUID(), workingDirectory: "/tmp", restoresScrollback: false, restoresHistory: true, launch: .shell)

        _ = restore.execute(plan(historyOnly), savedAt: saved, home: SessionFixtures.directory("/Users/s"))

        #expect(
            engine.openedSpecs.first?.restoration
                == PaneRestoration(scrollback: nil, restoresHistory: true, savedAt: saved))
    }

    @Test func aNamedLayoutBringsBackNoHistory() throws {
        let layouts = InMemoryNamedLayouts()
        let name = try LayoutName("plantilla")
        try layouts.save(
            WorkspaceSnapshot(
                name: "w", rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: 0,
                panes: [
                    PaneSnapshot(
                        id: UUID(), workingDirectory: "/tmp", title: nil, processName: nil, scrollbackLines: 10,
                        commandCount: 1, relaunch: nil, agent: nil)
                ]), as: name)
        var set = WorkspaceSet(
            first: .empty(name: "home", rootDirectory: SessionFixtures.directory("/Users/s"), layout: DwindleLayout()))

        _ = try RestoreNamedLayout(layouts: layouts, restore: restore).execute(
            name, into: &set, home: SessionFixtures.directory("/Users/s"))

        #expect(engine.openedSpecs.first?.restoration == nil)
        #expect(archive.scrollbackLookups.isEmpty)
    }

    // MARK: Agents and attention

    @Test func activatingAPaneInTheActiveWorkspaceMovesFocus() {
        let first = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        let second = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        var set = WorkspaceSet(
            first: Workspace.empty(name: "w", rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout())
                .adding(first).adding(second))

        _ = ActivatePane(engine: engine).execute(first.id, in: &set)

        #expect(set.active.focusedPane == first.id)
    }

    @Test func countsDistinguishEachState() {
        func pane(_ hook: AgentHook) -> Pane {
            let base = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
            return base.applying(
                AgentEvent(pane: base.id, hook: hook, at: .now, sessionID: UUID().uuidString, prompt: "x", message: "m")
            ).0
        }
        let panes = [pane(.userPromptSubmit), pane(.stop), pane(.stop), pane(.stop), pane(.sessionEnd)]
        let workspace = panes.reduce(
            Workspace.empty(name: "w", rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout())
        ) { $0.adding($1) }

        #expect(AgentCounts.of(WorkspaceSet(first: workspace)) == AgentCounts(working: 1, waiting: 3, failed: 0))
    }

    @Test func aPromptStartingWithABlankLineIsTitledByItsFirstText() {
        let base = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))

        let titled = base.applying(
            AgentEvent(pane: base.id, hook: .userPromptSubmit, at: .now, sessionID: "s", prompt: "\nhola")
        ).0

        #expect(titled.agent?.title == "hola")
    }

    @Test func aSessionStartForAnotherSessionReplacesTheAgent() {
        let base = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        let first = base.applying(
            AgentEvent(pane: base.id, hook: .userPromptSubmit, at: .now, sessionID: "a", prompt: "x")
        ).0

        let second = first.applying(AgentEvent(pane: base.id, hook: .sessionStart, at: .now, sessionID: "b")).0

        #expect(second.agent?.sessionID == "b")
        #expect(second.agent?.title == nil)
    }

    // MARK: Text

    @Test func blankLinesCountInTheScrollback() {
        #expect(Scrollback(text: "a\n\nb", format: .plain).lineCount == 3)
    }

    @Test func savedLayoutCommandsAreNeverMarkedCurrent() throws {
        let set = WorkspaceSet(
            first: .empty(name: "w", rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout()))
        let commands = CommandCatalog.commands(
            for: CatalogState(
                workspaces: set,
                savedLayouts: [NamedLayoutSummary(name: try LayoutName("x"), paneCount: 1, agentCount: 0)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        #expect(commands.first { $0.title.hasPrefix("Restaurar layout") }?.isCurrent == false)
        #expect(CommandCatalog.saveCommand(named: "nuevo", texts: .spanish)?.isCurrent == false)
    }

    @Test func layoutSummaryCountsOnlyPanesWithAgents() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "s", title: nil, lastState: .working)
        func pane(_ agent: AgentSnapshot?) -> PaneSnapshot {
            PaneSnapshot(
                id: UUID(), workingDirectory: "/tmp", title: nil, processName: nil, scrollbackLines: 0, commandCount: 0,
                relaunch: nil, agent: agent)
        }
        let layout = WorkspaceSnapshot(
            name: "w", rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: 0,
            panes: [pane(agent), pane(nil), pane(nil)])

        #expect(
            NamedLayoutSummary(name: (try? LayoutName("w")) ?? { preconditionFailure() }(), layout: layout).agentCount
                == 1)
    }

    @Test func aRelaunchRowIsNotFinished() {
        let pane = PaneSnapshot(
            id: UUID(), workingDirectory: "/tmp", title: nil, processName: "node", scrollbackLines: 0, commandCount: 0,
            relaunch: RelaunchCommand(arguments: ["pnpm", "dev"]), agent: nil)
        let snapshot = SessionSnapshot(
            version: 1, savedAt: .now,
            workspaces: [
                WorkspaceSnapshot(
                    name: "w", rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: 0, panes: [pane])
            ],
            activeIndex: 0)

        let row = ResumeListing.workspaces(
            in: snapshot, home: SessionFixtures.directory("/Users/s"), harnesses: HarnessRegistry([])
        ).first?.rows.first

        #expect(row?.isFinished == false)
    }
}
