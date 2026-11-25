import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Capture harness session")
struct CaptureHarnessSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let directory = "/private/tmp/w"

    /// A clock that advances when the capture sleeps, and a store whose sessions appear at given times.
    final class World: @unchecked Sendable {
        var now: Date
        var sessions: [(appearsAt: Date, session: HarnessSession)] = []
        var sleeps = 0
        var failure: HarnessError?
        init(now: Date) { self.now = now }
        var visible: [HarnessSession] { sessions.filter { $0.appearsAt <= now }.map(\.session) }
    }

    struct WorldAdapter: HarnessAdapter {
        let world: World
        let harness = HarnessID.codex
        func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["codex"]) }
        func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
            if let failure = world.failure { throw failure }
            return SessionCatalog.merge([.success(world.visible)], query: query).sessions
        }
        func resumeCommand(sessionID: String) -> String { "codex resume \(sessionID)" }
        func continueCommand() -> String { "codex resume --last" }
        func forkCommand(sessionID: String) -> String? { nil }
        func sessionID(fromCommandLine arguments: [String]) -> String? {
            ProcessNames.value(after: ["resume"], in: arguments)
        }
    }

    private func session(_ id: String, created offset: TimeInterval) -> HarnessSession {
        let created = t0.addingTimeInterval(offset)
        return HarnessSession(
            harness: .codex, id: id, directory: directory, title: id, createdAt: created, updatedAt: created,
            detail: nil)
    }

    private func make(_ world: World, resolve: @escaping (String) -> String = { $0 }) -> CaptureHarnessSession {
        CaptureHarnessSession(
            registry: HarnessRegistry([WorldAdapter(world: world)]), clock: { world.now },
            sleep: { duration in
                world.sleeps += 1
                world.now = world.now.addingTimeInterval(TimeInterval(duration.components.seconds))
            }, resolve: resolve)
    }

    private func pane(pending: HarnessBinding? = nil) throws -> Pane {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: directory))
        return pending.map(pane.binding) ?? pane
    }

    private func codex(_ arguments: [String] = ["codex"], startedAt offset: TimeInterval = 0, pid: Int32 = 42)
        -> ForegroundProcess
    {
        ForegroundProcess(name: "codex", commandLine: arguments, pid: pid, startedAt: t0.addingTimeInterval(offset))
    }

    private func pending(_ id: String?) -> HarnessBinding {
        HarnessBinding(harness: .codex, sessionID: id, processStartedAt: t0, pid: nil)
    }

    private func capture(
        _ capture: CaptureHarnessSession, _ start: CaptureStart, competitors: Int = 0,
        claimed: Set<String> = [], running: @escaping () -> Bool = { true }
    ) async -> HarnessBinding? {
        await capture.capture(
            start,
            CaptureContext(
                competitors: { competitors }, claimed: { claimed }, isStillRunning: running, disputed: { _ in }))
    }

    @Test func pendingIdFromRestoreIsKeptAndBoundToTheProcess() async throws {
        let world = World(now: t0)
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(pending: pending("restored")), to: codex()))

        let binding = await capture(session, start)

        #expect(binding == HarnessBinding(harness: .codex, sessionID: "restored", processStartedAt: t0, pid: 42))
        #expect(world.sleeps == 0)
    }

    @Test func idFromCommandLineWins() async throws {
        let session = make(World(now: t0))

        let start = try #require(session.processChanged(in: try pane(), to: codex(["codex", "resume", "0198"])))

        #expect(start.decision == .known("0198"))
    }

    @Test func continuePaneNeverCapturesAnotherPanesSession() async throws {
        let world = World(now: t0.addingTimeInterval(30))
        world.sessions = [(t0, session("other-pane", created: 5))]
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(pending: pending(nil)), to: codex()))

        let binding = await capture(session, start)

        #expect(start.decision == .continuing)
        #expect(binding?.sessionID == nil)
        #expect(binding?.harness == .codex)
        #expect(world.sleeps == 0)
    }

    @Test func boundBindingOfAFinishedProcessIsNotReused() async throws {
        let old = HarnessBinding(harness: .codex, sessionID: "old", processStartedAt: t0, pid: 7)
        let session = make(World(now: t0))

        let start = try #require(session.processChanged(in: try pane(pending: old), to: codex(pid: 42)))

        #expect(start.decision == .search)
    }

    @Test func capturesWhenSessionAppearsLater() async throws {
        let world = World(now: t0)
        world.sessions = [(t0.addingTimeInterval(5), session("new", created: 4))]
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        let binding = await capture(session, start)

        #expect(binding?.sessionID == "new")
        #expect(binding?.pid == 42)
        #expect(world.sleeps == 3)
    }

    @Test func givesUpAfterTenMinutesKeepingTheHarnessForTheFallback() async throws {
        let world = World(now: t0)
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        let binding = await capture(session, start)

        #expect(binding == HarnessBinding(harness: .codex, sessionID: nil, processStartedAt: t0, pid: 42))
        #expect(world.now >= t0.addingTimeInterval(CaptureHarnessSession.giveUpAfter))
        #expect(world.now < t0.addingTimeInterval(CaptureHarnessSession.giveUpAfter + 3))
    }

    @Test func stopsWhenProcessLeaves() async throws {
        let world = World(now: t0)
        world.sessions = [(t0.addingTimeInterval(60), session("late", created: 59))]
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        let binding = await capture(session, start, running: { world.sleeps < 2 })

        #expect(binding == nil)
    }

    @Test func neverTakesSessionBeforeStartMinusMargin() async throws {
        let world = World(now: t0.addingTimeInterval(1))
        world.sessions = [(t0, session("older", created: -3))]
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        let binding = await capture(session, start, running: { world.sleeps < 3 })

        #expect(binding == nil)
    }

    @Test func earlierPaneTypingFirstNeverLosesItsSession() async throws {
        let world = World(now: t0.addingTimeInterval(40))
        world.sessions = [(t0, session("a-typed-first", created: 30))]
        let session = make(world)
        let early = try #require(session.processChanged(in: try pane(), to: codex(startedAt: 0)))
        let late = try #require(session.processChanged(in: try pane(), to: codex(startedAt: 10, pid: 43)))

        let first = await capture(session, early, competitors: 1)
        let second = await capture(session, late, competitors: 1)

        #expect(first?.sessionID == nil)
        #expect(second?.sessionID == nil)
    }

    /// Final review C1: the pane that searches second finds no competitor left waiting, yet must not take the session
    /// the first one gave up because of it.
    @Test func disputedSessionIsNeverTakenLater() async throws {
        let world = World(now: t0.addingTimeInterval(40))
        world.sessions = [(t0, session("typed-in-late", created: 30))]
        let session = make(world)
        let early = try #require(session.processChanged(in: try pane(), to: codex(startedAt: 0)))
        let late = try #require(session.processChanged(in: try pane(), to: codex(startedAt: 10, pid: 43)))
        var disputed: Set<String> = []

        let lateBinding = await session.capture(
            late,
            CaptureContext(
                competitors: { 1 }, claimed: { disputed }, isStillRunning: { true },
                disputed: { disputed.insert($0) }))
        let earlyBinding = await session.capture(
            early,
            CaptureContext(
                competitors: { 0 }, claimed: { disputed }, isStillRunning: { true },
                disputed: { disputed.insert($0) }))

        #expect(lateBinding?.sessionID == nil)
        #expect(disputed == ["typed-in-late"])
        #expect(earlyBinding?.sessionID == nil)
    }

    @Test func restoredPaneKeepsIdWhileNewPaneCapturesFreshOne() async throws {
        let world = World(now: t0.addingTimeInterval(30))
        world.sessions = [(t0, session("restored", created: -3600)), (t0, session("fresh", created: 5))]
        let session = make(world)
        let restored = try #require(session.processChanged(in: try pane(pending: pending("restored")), to: codex()))
        let fresh = try #require(session.processChanged(in: try pane(), to: codex(startedAt: 2, pid: 43)))

        let kept = await capture(session, restored)
        let captured = await capture(session, fresh, claimed: ["restored"])

        #expect(kept?.sessionID == "restored")
        #expect(captured?.sessionID == "fresh")
    }

    @Test func missingStoreGoesToTheFallbackAtOnce() async throws {
        let world = World(now: t0)
        world.failure = .storeMissing(harness: .codex, path: "/c")
        let session = make(world)
        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        let binding = await capture(session, start)

        #expect(binding?.sessionID == nil)
        #expect(world.sleeps == 0)
    }

    @Test func directoryIsResolvedBeforeComparing() throws {
        let session = make(World(now: t0), resolve: { $0 == self.directory ? "/Volumes/real/w" : $0 })

        let start = try #require(session.processChanged(in: try pane(), to: codex()))

        #expect(start.directory == "/Volumes/real/w")
    }

    @Test func claudeHookIdOverridesDiskCapture() throws {
        let claude = CaptureHarnessSession(
            registry: HarnessRegistry([FakeHarnessAdapter()]), clock: { self.t0 }, sleep: { _ in })
        let hooked = try pane().applying(
            AgentEvent(pane: PaneID(), hook: .sessionStart, at: t0, sessionID: "from-hook")
        ).0

        #expect(claude.processChanged(in: hooked, to: ForegroundProcess(name: "fake")) == nil)
    }

    @Test func otherProcessesAreNotCaptured() throws {
        #expect(make(World(now: t0)).processChanged(in: try pane(), to: ForegroundProcess(name: "vim")) == nil)
    }

    @Test func missingStartTimeUsesTheClock() throws {
        let session = make(World(now: t0.addingTimeInterval(7)))

        let start = try #require(session.processChanged(in: try pane(), to: ForegroundProcess(name: "codex")))

        #expect(start.processStartedAt == t0.addingTimeInterval(7))
    }
}

@Suite("Pane harness binding")
struct PaneHarnessTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func returningToShellKeepsLastBindingForSaving() throws {
        let binding = HarnessBinding(harness: .codex, sessionID: "x", processStartedAt: t0, pid: nil)
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "codex")))
            .binding(binding)

        let back = pane.applying(.foregroundProcessChanged(ForegroundProcess(name: "zsh")), at: t0)

        #expect(back.harnessBinding == binding)
    }

    @Test func foregroundProcessCarriesPidAndStart() {
        let process = ForegroundProcess(name: "codex", commandLine: nil, pid: 7, startedAt: t0)

        #expect(process.pid == 7)
        #expect(process.startedAt == t0)
        #expect(ForegroundProcess(name: "zsh").pid == nil)
    }

    private func paneThatRanClaude(state: AgentState) throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
            .attaching(AgentSession(harness: .claude, sessionID: "old", title: nil, state: state, startedAt: t0))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "codex", pid: 42)))
    }

    /// Final review I1: a Claude that finished in the pane does not stop the capture of the Codex run after it.
    @Test func stoppedAgentOfAnotherHarnessLetsTheCaptureRun() throws {
        let pane = try paneThatRanClaude(state: .stopped)

        #expect(pane.runsHarness(.codex, pid: 42))
        #expect(!pane.runsHarness(.codex, pid: 43))
        #expect(!pane.runsHarness(.claude, pid: 42))
    }

    @Test func codexAfterAFinishedClaudeIsSavedAsCodex() throws {
        let binding = HarnessBinding(harness: .codex, sessionID: "fresh", processStartedAt: t0, pid: 42)
        let pane = try paneThatRanClaude(state: .stopped).binding(binding)

        let saved = PaneSnapshot(pane, scrollbackLines: 0)

        #expect(saved.agent?.harness == .codex)
        #expect(saved.agent?.sessionID == "fresh")
    }

    /// A stopped agent still in its own process, with no other harness bound, is saved as itself.
    @Test func stoppedAgentInItsProcessIsSavedAsTheAgent() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
            .attaching(AgentSession(harness: .claude, sessionID: "old", title: nil, state: .stopped, startedAt: t0))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "claude", pid: 42)))

        #expect(PaneSnapshot(pane, scrollbackLines: 0).agent?.sessionID == "old")
    }

    @Test func paneRemembersTheForegroundPid() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "codex", pid: 42)))

        #expect(pane.foregroundPID == 42)
    }
}

@Suite("Workspace harness binding")
struct WorkspaceHarnessBindingTests {
    @Test func bindingReachesOnlyItsPane() throws {
        let first = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
        let second = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w"))
        let workspace = Workspace.empty(
            name: "w", rootDirectory: try WorkingDirectory(path: "/w"), layout: DwindleLayout()
        )
        .adding(first).adding(second)
        let binding = HarnessBinding(harness: .codex, sessionID: "x", processStartedAt: .now, pid: 4)

        let bound = workspace.binding(binding, to: first.id)

        #expect(bound.panes.first { $0.id == first.id }?.harnessBinding == binding)
        #expect(bound.panes.first { $0.id == second.id }?.harnessBinding == nil)
    }
}

@Suite("Capture interim binding")
struct CaptureInterimBindingTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func start(_ decision: CaptureDecision) -> CaptureStart {
        CaptureStart(pane: PaneID(), harness: .codex, directory: "/w", processStartedAt: t0, pid: 9, decision: decision)
    }

    @Test func interimBindingHoldsWhatIsKnownAtTheStart() {
        #expect(start(.known("x")).interimBinding.sessionID == "x")
        #expect(start(.continuing).interimBinding.sessionID == nil)
        #expect(
            start(.search).interimBinding
                == HarnessBinding(harness: .codex, sessionID: nil, processStartedAt: t0, pid: 9))
    }
}
