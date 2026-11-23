import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("RestoreSession")
struct RestoreSessionTests {
    private let engine = FakeTerminalEngine()
    private let archive = InMemorySessionArchive()
    private let home = SessionFixtures.directory("/Users/s")
    private let files = PaneFileLocator(stateDirectory: URL(filePath: "/state"))

    private var restore: RestoreSession {
        RestoreSession(
            .init(
                engine: engine, transcripts: archive, harnesses: HarnessRegistry([FakeHarnessAdapter()]),
                environment: PaneEnvironment(version: "2", files: files), shell: .custom("/bin/zsh -f"),
                clock: { SessionFixtures.now }))
    }

    private func run(_ workspaces: [PlannedWorkspace], activeIndex: Int = 0) -> RestoreResult {
        restore.execute(
            RestorePlan(workspaces: workspaces, activeIndex: activeIndex), savedAt: SessionFixtures.savedAt,
            home: home)
    }

    @Test func restoreKeepsPaneIdentity() {
        let id = UUID()

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(id: id)])])

        #expect(result.set?.active.panes.map(\.id) == [PaneID(rawValue: id)])
        #expect(engine.openedIDs == [PaneID(rawValue: id)])
    }

    @Test func restoreFeedsScrollbackOnlyWhenPlanned() {
        let shell = SessionFixtures.pane()
        let agent = SessionFixtures.pane(
            launch: .resume(AgentSnapshot(harness: .claude, sessionID: "7f3a", title: nil, lastState: .working)))
        let text = Scrollback(text: "salida", format: .vt)
        archive.transcripts[PaneID(rawValue: shell.id)] = text
        archive.transcripts[PaneID(rawValue: agent.id)] = text

        _ = run([SessionFixtures.workspace("solen", [shell, agent])])

        #expect(
            engine.openedSpecs[0].restoration
                == PaneRestoration(scrollback: text, restoresHistory: true, savedAt: SessionFixtures.savedAt))
        #expect(engine.openedSpecs[1].restoration?.scrollback == nil)
    }

    @Test func restoreResumesAgentWithHarnessCommand() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: "Recordatorios", lastState: .working)

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(launch: .resume(agent))])])

        #expect(engine.openedSpecs[0].initialInput == "fake --resume 7f3a\n")
        let session = result.set?.active.panes.first?.agent
        #expect(session?.sessionID == "7f3a")
        #expect(session?.title == "Recordatorios")
        #expect(session?.state == .waiting(since: SessionFixtures.now, reason: .turnFinished))
    }

    @Test func agentOfUnknownHarnessOpensAPlainShellAndIsReported() {
        let agent = AgentSnapshot(
            harness: HarnessID(rawValue: "codex"), sessionID: "1", title: nil, lastState: .working)

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(launch: .resume(agent))])])

        #expect(engine.openedSpecs[0].initialInput == nil)
        #expect(result.failures.count == 1)
    }

    @Test func restoreRelaunchesCommand() {
        let command = RelaunchCommand(arguments: ["pnpm", "dev"])

        _ = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(launch: .relaunch(command))])])

        #expect(engine.openedSpecs[0].initialInput == "pnpm dev\n")
    }

    @Test func restoreUsesSavedRatios() {
        let tree = SnapshotTree.split(axis: .sideBySide, ratio: 0.8, first: .leaf(index: 0), second: .leaf(index: 1))
        let panes = [SessionFixtures.pane(), SessionFixtures.pane()]

        let result = run([SessionFixtures.workspace("solen", panes, tree: tree, focusedIndex: 0)])

        let ids = panes.map { PaneID(rawValue: $0.id) }
        #expect(
            result.set?.active.tree
                == .split(axis: .sideBySide, ratio: Ratio(0.8), first: .leaf(ids[0]), second: .leaf(ids[1])))
        #expect(result.set?.active.focusedPane == ids[0])
    }

    @Test func restoreRebuildsTreeWhenNil() {
        let panes = [SessionFixtures.pane(), SessionFixtures.pane()]

        let result = run([SessionFixtures.workspace("solen", panes)])

        let ids = panes.map { PaneID(rawValue: $0.id) }
        #expect(result.set?.active.tree == DwindleLayout().tree(for: ids))
    }

    @Test func missingDirectoryFallsBackToRootThenHome() {
        engine.failingDirectories = ["/Users/s/dev/borrada", "/Users/s/dev/solen"]

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane("/Users/s/dev/borrada")])])

        #expect(engine.openedSpecs.map(\.workingDirectory.path) == ["/Users/s"])
        #expect(result.set?.active.panes.first?.workingDirectory.path == "/Users/s")
    }

    @Test func paneThatCannotOpenAnywhereIsReportedAndSkipped() {
        engine.failingDirectories = ["/Users/s/dev/solen", "/Users/s"]
        let ok = SessionFixtures.pane("/tmp")

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(), ok])])

        #expect(result.set?.active.panes.map(\.id) == [PaneID(rawValue: ok.id)])
        #expect(result.failures.count == 1)
    }

    @Test func workspacesKeepOrderAndActiveOneHidesTheRest() {
        let first = SessionFixtures.pane()
        let second = SessionFixtures.pane()

        let result = run(
            [SessionFixtures.workspace("solen", [first]), SessionFixtures.workspace("rizaria", [second])],
            activeIndex: 1)

        #expect(result.set?.workspaces.map(\.name) == ["solen", "rizaria"])
        #expect(result.set?.active.name == "rizaria")
        #expect(engine.hiddenPanes == [PaneID(rawValue: first.id)])
    }

    @Test func emptyPlanGivesNoSet() {
        #expect(run([]).set == nil)
    }

    @Test func paneEnvironmentCarriesPaneIDAndHistoryFile() {
        let id = UUID()

        _ = run([SessionFixtures.workspace("solen", [SessionFixtures.pane(id: id)])])

        let environment = engine.openedSpecs[0].environment
        #expect(environment["SMALTI_PANE_ID"] == id.uuidString)
        #expect(environment["SMALTI_HISTORY_FILE"] == "/state/history/\(id.uuidString).zsh_history")
        #expect(environment["SMALTI"] == "1")
    }

    @Test func rootThatCannotOpenMakesHomeTheWorkspaceRoot() {
        engine.failingDirectories = ["/Users/s/dev/borrada", "/Users/s/dev/solen"]

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane("/Users/s/dev/borrada")])])

        #expect(result.set?.active.rootDirectory.path == "/Users/s")
    }

    @Test func activeWorkspaceIsKeptWhenAnEarlierOneFailsToOpen() {
        engine.failingDirectories = ["/Users/s/dev/solen", "/Users/s"]

        let result = run(
            [
                SessionFixtures.workspace("solen", [SessionFixtures.pane()]),
                SessionFixtures.workspace("rizaria", [SessionFixtures.pane("/tmp/r")]),
                SessionFixtures.workspace("xolken", [SessionFixtures.pane("/tmp/x")]),
            ], activeIndex: 1)

        #expect(result.set?.active.name == "rizaria")
    }

    @Test func focusStaysOnThePlannedPaneWhenAnEarlierOneFails() {
        engine.failingDirectories = ["/Users/s/dev/borrada", "/Users/s/dev/solen", "/Users/s"]
        let focused = SessionFixtures.pane("/tmp/a")

        let result = run(
            [
                SessionFixtures.workspace(
                    "solen", [SessionFixtures.pane("/Users/s/dev/borrada"), focused, SessionFixtures.pane("/tmp/b")],
                    focusedIndex: 1)
            ])

        #expect(result.set?.active.focusedPane == PaneID(rawValue: focused.id))
    }

    @Test func failureNamesTheEngineError() {
        engine.failingDirectories = ["/Users/s/dev/solen", "/Users/s"]

        let result = run([SessionFixtures.workspace("solen", [SessionFixtures.pane()])])

        #expect(result.failures.first?.contains("no such directory") == true)
    }

    @Test func restoreUsesTheConfiguredShell() {
        _ = run([SessionFixtures.workspace("solen", [SessionFixtures.pane()])])

        #expect(engine.openedSpecs.first?.command == .custom("/bin/zsh -f"))
    }
}
