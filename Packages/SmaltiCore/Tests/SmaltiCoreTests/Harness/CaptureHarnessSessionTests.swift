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
        init(now: Date) { self.now = now }
        var visible: [HarnessSession] { sessions.filter { $0.appearsAt <= now }.map(\.session) }
    }

    struct WorldAdapter: HarnessAdapter {
        let world: World
        let harness = HarnessID.codex
        func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["codex"]) }
        func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
            SessionCatalog.merge([.success(world.visible)], query: query).sessions
        }
        func resumeCommand(for agent: AgentSnapshot) -> String { "codex resume \(agent.sessionID)" }
        func continueCommand() -> String { "codex resume --last" }
        func forkCommand(for agent: AgentSnapshot) -> String? { nil }
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

    private func make(_ world: World) -> CaptureHarnessSession {
        CaptureHarnessSession(
            registry: HarnessRegistry([WorldAdapter(world: world)]), clock: { world.now },
            sleep: { duration in
                world.sleeps += 1
                world.now = world.now.addingTimeInterval(TimeInterval(duration.components.seconds))
            })
    }

    private func pane() throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: directory))
    }

    private func codex(_ arguments: [String] = ["codex"], startedAt offset: TimeInterval = 0) -> ForegroundProcess {
        ForegroundProcess(name: "codex", commandLine: arguments, pid: 42, startedAt: t0.addingTimeInterval(offset))
    }

    @Test func knownIdIsKept() async throws {
        let world = World(now: t0)
        let capture = make(world)

        let start = capture.processChanged(in: try pane(), to: codex(), knownID: "restored")
        let binding = await capture.capture(try #require(start), claimed: { [] }, isStillRunning: { true })

        #expect(binding == HarnessBinding(harness: .codex, sessionID: "restored", processStartedAt: t0))
        #expect(world.sleeps == 0)
    }

    @Test func idFromCommandLineWins() async throws {
        let capture = make(World(now: t0))

        let start = try #require(
            capture.processChanged(in: try pane(), to: codex(["codex", "resume", "0198"]), knownID: nil))

        #expect(start.decided == "0198")
    }

    @Test func capturesWhenSessionAppearsLater() async throws {
        let world = World(now: t0)
        world.sessions = [(t0.addingTimeInterval(5), session("new", created: 4))]
        let capture = make(world)
        let start = try #require(capture.processChanged(in: try pane(), to: codex(), knownID: nil))

        let binding = await capture.capture(start, claimed: { [] }, isStillRunning: { true })

        #expect(binding?.sessionID == "new")
        #expect(world.sleeps == 3)
    }

    @Test func stopsRetryingAfterTenMinutes() async throws {
        let world = World(now: t0)
        let capture = make(world)
        let start = try #require(capture.processChanged(in: try pane(), to: codex(), knownID: nil))

        let binding = await capture.capture(start, claimed: { [] }, isStillRunning: { true })

        #expect(binding == nil)
        #expect(world.now >= t0.addingTimeInterval(CaptureHarnessSession.giveUpAfter))
        #expect(world.now < t0.addingTimeInterval(CaptureHarnessSession.giveUpAfter + 3))
    }

    @Test func stopsWhenProcessLeaves() async throws {
        let world = World(now: t0)
        world.sessions = [(t0.addingTimeInterval(60), session("late", created: 59))]
        let capture = make(world)
        let start = try #require(capture.processChanged(in: try pane(), to: codex(), knownID: nil))

        let binding = await capture.capture(start, claimed: { [] }, isStillRunning: { world.sleeps < 2 })

        #expect(binding == nil)
    }

    @Test func neverTakesSessionBeforeStartMinusMargin() async throws {
        let world = World(now: t0.addingTimeInterval(1))
        world.sessions = [(t0, session("older", created: -3))]
        let capture = make(world)
        let start = try #require(capture.processChanged(in: try pane(), to: codex(), knownID: nil))

        let binding = await capture.capture(start, claimed: { [] }, isStillRunning: { world.sleeps < 3 })

        #expect(binding == nil)
    }

    @Test func twoPanesSameDirectoryGetDistinctIds() async throws {
        let world = World(now: t0.addingTimeInterval(30))
        world.sessions = [(t0, session("second", created: 12)), (t0, session("first", created: 3))]
        let capture = make(world)
        let early = try #require(capture.processChanged(in: try pane(), to: codex(startedAt: 0), knownID: nil))
        let late = try #require(capture.processChanged(in: try pane(), to: codex(startedAt: 10), knownID: nil))

        let first = await capture.capture(
            early, laterStarts: [late.processStartedAt], claimed: { [] },
            isStillRunning: { true })
        let second = await capture.capture(
            late, claimed: { Set([first?.sessionID].compactMap { $0 }) },
            isStillRunning: { true })

        #expect(first?.sessionID == "first")
        #expect(second?.sessionID == "second")
    }

    @Test func restoredPaneKeepsIdWhileNewPaneCapturesFreshOne() async throws {
        let world = World(now: t0.addingTimeInterval(30))
        world.sessions = [(t0, session("restored", created: -3600)), (t0, session("fresh", created: 5))]
        let capture = make(world)
        let restored = try #require(capture.processChanged(in: try pane(), to: codex(), knownID: "restored"))
        let fresh = try #require(capture.processChanged(in: try pane(), to: codex(startedAt: 2), knownID: nil))

        let kept = await capture.capture(restored, claimed: { [] }, isStillRunning: { true })
        let captured = await capture.capture(fresh, claimed: { ["restored"] }, isStillRunning: { true })

        #expect(kept?.sessionID == "restored")
        #expect(captured?.sessionID == "fresh")
    }

    @Test func claudeHookIdOverridesDiskCapture() throws {
        let claude = CaptureHarnessSession(
            registry: HarnessRegistry([FakeHarnessAdapter()]), clock: { self.t0 }, sleep: { _ in })
        let hooked = try pane().applying(
            AgentEvent(pane: PaneID(), hook: .sessionStart, at: t0, sessionID: "from-hook")
        ).0

        #expect(claude.processChanged(in: hooked, to: ForegroundProcess(name: "fake"), knownID: nil) == nil)
    }

    @Test func otherProcessesAreNotCaptured() throws {
        let capture = make(World(now: t0))

        #expect(capture.processChanged(in: try pane(), to: ForegroundProcess(name: "vim"), knownID: nil) == nil)
    }

    @Test func missingStartTimeUsesTheClock() throws {
        let capture = make(World(now: t0.addingTimeInterval(7)))

        let start = try #require(
            capture.processChanged(in: try pane(), to: ForegroundProcess(name: "codex"), knownID: nil))

        #expect(start.processStartedAt == t0.addingTimeInterval(7))
    }
}

@Suite("Pane harness binding")
struct PaneHarnessTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func returningToShellKeepsLastBindingForSaving() throws {
        let binding = HarnessBinding(harness: .codex, sessionID: "x", processStartedAt: t0)
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
}
