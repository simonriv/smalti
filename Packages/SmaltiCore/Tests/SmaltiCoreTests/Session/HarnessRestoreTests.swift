import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// A harness without hooks (no state), resuming with `codex resume <id>` and continuing with `codex resume --last`.
struct CodexLikeHarness: HarnessAdapter {
    let harness = HarnessID.codex
    func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["codex"]) }
    func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] { [] }
    func resumeCommand(sessionID: String) -> String { "codex resume \(sessionID)" }
    func continueCommand() -> String { "codex resume --last" }
    func forkCommand(sessionID: String) -> String? { nil }
    func sessionID(fromCommandLine arguments: [String]) -> String? { nil }
}

/// Claude-like: resumes with `--ide` when an editor is connected.
struct EditorAwareHarness: HarnessAdapter, EditorConnectable {
    let harness = HarnessID.claude
    func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["claude"]) }
    func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] { [] }
    func resumeCommand(sessionID: String) -> String { "claude --resume \(sessionID)" }
    func resumeCommandConnectingEditor(sessionID: String) -> String { resumeCommand(sessionID: sessionID) + " --ide" }
    func continueCommand() -> String { "claude --continue" }
    func forkCommand(sessionID: String) -> String? { nil }
    func sessionID(fromCommandLine arguments: [String]) -> String? { nil }
}

@MainActor
@Suite("Harness restore")
struct HarnessRestoreTests {
    private let engine = FakeTerminalEngine()
    private let archive = InMemorySessionArchive()
    private let home = SessionFixtures.directory("/Users/s")
    private let files = PaneFileLocator(stateDirectory: URL(filePath: "/state"))

    private func restore(connectsEditor: Bool = false) -> RestoreSession {
        RestoreSession(
            .init(
                engine: engine, transcripts: archive,
                harnesses: HarnessRegistry([CodexLikeHarness(), EditorAwareHarness()]),
                environment: PaneEnvironment(version: "2", files: files), shell: .custom("/bin/zsh -f"),
                clock: { SessionFixtures.now }, connectsEditor: connectsEditor))
    }

    private func run(_ launch: PaneLaunch, connectsEditor: Bool = false) -> RestoreResult {
        restore(connectsEditor: connectsEditor).execute(
            RestorePlan(
                workspaces: [SessionFixtures.workspace("solen", [SessionFixtures.pane(launch: launch)])],
                activeIndex: 0),
            savedAt: SessionFixtures.savedAt, home: home)
    }

    @Test func paneWithIdResumes() {
        let result = run(.resume(AgentSnapshot(harness: .codex, sessionID: "0198", title: nil, lastState: nil)))

        #expect(engine.openedSpecs[0].initialInput == "codex resume 0198\n")
        let pane = result.set?.active.panes.first
        #expect(pane?.harnessBinding?.sessionID == "0198")
        #expect(pane?.harnessBinding?.pid == nil)
        #expect(pane?.agent == nil)
    }

    @Test func paneWithoutIdContinues() {
        let result = run(.resume(AgentSnapshot(harness: .codex, sessionID: nil, title: nil, lastState: nil)))

        #expect(engine.openedSpecs[0].initialInput == "codex resume --last\n")
        #expect(result.set?.active.panes.first?.harnessBinding?.harness == .codex)
        #expect(result.set?.active.panes.first?.harnessBinding?.sessionID == nil)
    }

    @Test func claudeGetsIdeFlagWhenEnabled() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: nil, lastState: .waiting)

        _ = run(.resume(agent), connectsEditor: true)

        #expect(engine.openedSpecs[0].initialInput == "claude --resume 7f3a --ide\n")
    }

    @Test func claudeWithoutEditorHasNoIdeFlag() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: nil, lastState: .waiting)

        let result = run(.resume(agent))

        #expect(engine.openedSpecs[0].initialInput == "claude --resume 7f3a\n")
        #expect(result.set?.active.panes.first?.agent?.sessionID == "7f3a")
    }

    @Test func editorPaneRelaunchesAtItsLine() {
        _ = run(.editor(EditorPosition(file: "/Users/s/dev/solen/src/a b.ts", line: 42)))

        #expect(engine.openedSpecs[0].initialInput == "nvim +42 '/Users/s/dev/solen/src/a b.ts'\n")
    }
}

@Suite("Harness resume rows")
struct HarnessResumeRowTests {
    private let home = SessionFixtures.directory("/Users/s")

    private func row(agent: AgentSnapshot? = nil, editor: EditorPosition? = nil, process: String = "codex")
        -> ResumeRow?
    {
        let pane = PaneSnapshot(
            id: UUID(), workingDirectory: "/Users/s/dev/solen", title: nil, processName: process, scrollbackLines: 0,
            commandCount: 0, relaunch: nil, agent: agent, editor: editor)
        let workspace = WorkspaceSnapshot(
            name: "solen", rootDirectory: "/Users/s/dev/solen", layout: "dwindle", tree: nil, focusedIndex: 0,
            panes: [pane])
        return ResumeListing.workspaces(
            in: SessionSnapshot(version: 2, savedAt: .now, workspaces: [workspace], activeIndex: 0), home: home,
            harnesses: HarnessRegistry([CodexLikeHarness()])
        ).first?.rows.first
    }

    @Test func continueRowWarnsLastOfDirectory() {
        let listed = row(agent: AgentSnapshot(harness: .codex, sessionID: nil, title: nil, lastState: nil))

        #expect(listed?.tag == ResumeTag(text: "Codex", kind: .agent))
        #expect(listed?.code == "codex resume --last")
        #expect(listed?.detail == "la última del directorio")
        #expect(listed?.isFinished == false)
    }

    @Test func statelessAgentDoesNotColorTheWorkspace() {
        let pane = PaneSnapshot(
            id: UUID(), workingDirectory: "/w", title: nil, processName: "codex", scrollbackLines: 0, commandCount: 0,
            relaunch: nil, agent: AgentSnapshot(harness: .codex, sessionID: "1", title: nil, lastState: nil))
        let workspace = WorkspaceSnapshot(
            name: "w", rootDirectory: "/w", layout: "dwindle", tree: nil, focusedIndex: 0, panes: [pane])

        let listed = ResumeListing.workspaces(
            in: SessionSnapshot(version: 2, savedAt: .now, workspaces: [workspace], activeIndex: 0), home: home,
            harnesses: HarnessRegistry([CodexLikeHarness()]))

        #expect(listed.first?.status == nil)
    }

    @Test func nvimRowShowsFileAndLine() {
        let listed = row(
            editor: EditorPosition(file: "/Users/s/dev/solen/src/reminder.service.ts", line: 42),
            process: "nvim")

        #expect(listed?.tag == ResumeTag(text: "nvim", kind: .program))
        #expect(listed?.title == "reminder.service.ts")
        #expect(listed?.detail == "línea 42")
        #expect(listed?.code == "nvim +42")
    }
}

@Suite("Harness pane snapshot")
struct HarnessPaneSnapshotTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func codexPane(id: String?, pid: Int32? = 42) throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "codex", commandLine: ["codex"], pid: pid)))
            .binding(HarnessBinding(harness: .codex, sessionID: id, processStartedAt: t0, pid: pid))
    }

    @Test func anotherProgramAfterTheHarnessIsSavedAsItself() throws {
        let pane = try codexPane(id: "old").applying(
            .foregroundProcessChanged(ForegroundProcess(name: "node", commandLine: ["npm", "run", "dev"], pid: 99)),
            at: t0)

        let snapshot = PaneSnapshot(pane, scrollbackLines: 0)

        #expect(snapshot.agent == nil)
        #expect(snapshot.relaunch == RelaunchCommand(arguments: ["npm", "run", "dev"]))
    }

    @Test func pendingRestoredBindingIsSavedWhileItsHarnessStarts() throws {
        let pane = try codexPane(id: "restored", pid: nil)

        #expect(PaneSnapshot(pane, scrollbackLines: 0).agent?.sessionID == "restored")
    }

    @Test func runningHarnessIsSavedAsStatelessAgent() throws {
        let snapshot = PaneSnapshot(try codexPane(id: "0198"), scrollbackLines: 0)

        #expect(snapshot.agent == AgentSnapshot(harness: .codex, sessionID: "0198", title: nil, lastState: nil))
        #expect(snapshot.relaunch == nil)
    }

    @Test func harnessBackAtTheShellIsSavedAsAShell() throws {
        let pane = try codexPane(id: "0198").applying(
            .foregroundProcessChanged(ForegroundProcess(name: "zsh")), at: t0)

        #expect(PaneSnapshot(pane, scrollbackLines: 0).agent == nil)
    }

    @Test func harnessWithoutIdIsSavedForTheFallback() throws {
        #expect(PaneSnapshot(try codexPane(id: nil), scrollbackLines: 0).agent?.sessionID == nil)
        #expect(PaneSnapshot(try codexPane(id: nil), scrollbackLines: 0).agent?.harness == .codex)
    }
}
