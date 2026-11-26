import Foundation
import SmaltiCore
import Testing

@Suite("Attention")
struct AttentionTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func pane(_ hook: AgentHook?, at seconds: TimeInterval = 0) -> Pane {
        let base = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/web"))
        guard let hook else { return base }
        let event = AgentEvent(
            pane: base.id, hook: hook, at: t0.addingTimeInterval(seconds), sessionID: UUID().uuidString, prompt: "x",
            toolSummary: "ls", message: "m")
        return base.applying(event).0
    }

    private func workspace(_ name: String, _ panes: [Pane]) -> Workspace {
        panes.reduce(
            Workspace.empty(name: name, rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout())
        ) {
            $0.adding($1)
        }
    }

    @Test func queueOrdersBySinceThenPosition() {
        let late = pane(.stop, at: 30)
        let early = pane(.permissionRequest, at: 10)
        let tieFirst = pane(.stop, at: 20)
        let tieSecond = pane(.stop, at: 20)
        let set = WorkspaceSet(first: workspace("a", [late, tieFirst])).adding(workspace("b", [early, tieSecond]))

        #expect(AttentionQueue.panes(in: set) == [early.id, tieFirst.id, tieSecond.id, late.id])
    }

    @Test func queueSkipsWorkingAndStopped() {
        let set = WorkspaceSet(
            first: workspace("a", [pane(.userPromptSubmit), pane(.sessionEnd), pane(nil), pane(.stopFailure)]))

        #expect(AttentionQueue.panes(in: set).count == 1)
    }

    @Test func countsAcrossWorkspaces() {
        let set = WorkspaceSet(first: workspace("a", [pane(.userPromptSubmit), pane(.stop)]))
            .adding(workspace("b", [pane(.userPromptSubmit), pane(.stopFailure), pane(nil)]))

        #expect(AgentCounts.of(set) == AgentCounts(working: 2, waiting: 1, failed: 1))
    }

    @Test func workspaceStatusPriority() {
        #expect(workspace("a", [pane(.userPromptSubmit), pane(.stop)]).agentStatus == .waiting)
        #expect(workspace("a", [pane(.stop), pane(.stopFailure)]).agentStatus == .failed)
        #expect(workspace("a", [pane(.sessionEnd), pane(.userPromptSubmit)]).agentStatus == .working)
        #expect(workspace("a", [pane(.sessionEnd)]).agentStatus == .stopped)
        #expect(workspace("a", [pane(nil)]).agentStatus == nil)
    }

    @Test func noticeTextsMatchSpec() {
        let directory = SessionFixtures.directory("/Users/s/dev/web")
        let id = PaneID()
        func body(_ reason: AttentionReason) -> String {
            AttentionNotice.make(reason, at: ("rizaria", directory, id), texts: .spanish).body
        }

        #expect(
            AttentionNotice.make(.turnFinished, at: ("rizaria", directory, id), texts: .spanish).title
                == "rizaria/web")
        #expect(
            body(.permission("pnpm db:migrate --name add_user_prefs"))
                == "pide permiso para `pnpm db:migrate --name add_user_prefs`")
        #expect(body(.permission("")) == "pide permiso")
        #expect(body(.turnFinished) == "terminó y te espera")
        #expect(body(.attention("Claude is waiting for your input")) == "Claude is waiting for your input")
        #expect(body(.failure("API error")) == "error: API error")
    }

    @Test func stopNotifiesOnlyWhenHidden() {
        #expect(AttentionPolicy.shouldNotify(.turnFinished, paneIsVisible: false))
        #expect(!AttentionPolicy.shouldNotify(.turnFinished, paneIsVisible: true))
        #expect(AttentionPolicy.shouldNotify(.permission("x"), paneIsVisible: true))
        #expect(AttentionPolicy.shouldNotify(.attention("x"), paneIsVisible: true))
        #expect(AttentionPolicy.shouldNotify(.failure("x"), paneIsVisible: true))
    }

    @Test(arguments: [(0.0, "0m"), (59, "0m"), (60, "1m"), (3599, "59m"), (3600, "1h 0m"), (4320, "1h 12m")])
    func elapsedTextBoundaries(seconds: TimeInterval, expected: String) {
        #expect(ElapsedText.short(since: t0, now: t0.addingTimeInterval(seconds)) == expected)
    }

    @Test func elapsedNeverGoesNegative() {
        #expect(ElapsedText.short(since: t0, now: t0.addingTimeInterval(-30)) == "0m")
    }
}
