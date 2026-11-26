import Foundation
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
        #expect(try workspace(panes: 3).statusLine(texts: .spanish) == "solen · 3 paneles · dwindle")
    }

    @Test func statusLineUsesSingularForOnePane() throws {
        #expect(try workspace(panes: 1).statusLine(texts: .spanish) == "solen · 1 panel · dwindle")
    }

    @Test func statusLineForEmptyWorkspace() throws {
        #expect(try workspace(panes: 0).statusLine(texts: .spanish) == "solen · 0 paneles · dwindle")
    }

    @Test func headerShowsProcessDirectoryAndShortcut() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/simon/dev/xolken"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "claude")))

        let header = PaneHeaderContent(
            pane, index: 3, context: HeaderContext(keymap: .standard, home: home, now: .now, texts: .spanish))

        #expect(
            header
                == PaneHeaderContent(
                    process: "claude", directory: "~/dev/xolken", status: nil, detail: nil, shortcut: "⌘3"))
    }

    /// F5 "Solo símbolo": the prompt's context replaces the directory in the header.
    @Test func promptContextReplacesTheDirectory() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/simon/dev/xolken"))
        var context = HeaderContext(keymap: .standard, home: home, now: .now, texts: .spanish)
        context.promptHeaders = [pane.id: "xolken · main +2"]

        let header = PaneHeaderContent(pane, index: 3, context: context)

        #expect(header.directory == "xolken · main +2")
    }

    @Test func headerWithoutIndexHasNoShortcut() throws {
        let pane = Pane(id: PaneID(), workingDirectory: home).applying(.titleChanged("vim notes.md"))

        let header = PaneHeaderContent(
            pane, index: nil, context: HeaderContext(keymap: .standard, home: home, now: .now, texts: .spanish))

        #expect(
            header == PaneHeaderContent(process: "vim notes.md", directory: "~", status: nil, detail: nil, shortcut: "")
        )
    }

    // MARK: - Agent state (F2)

    private func agentPane(_ hook: AgentHook, at start: Date) throws -> Pane {
        let base = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/s/dev/web"))
        return base.applying(
            AgentEvent(pane: base.id, hook: hook, at: start, sessionID: "s1", prompt: "x", message: "m")
        ).0
    }

    private func header(_ pane: Pane, now: Date) throws -> PaneHeaderContent {
        PaneHeaderContent(
            pane, index: 1,
            context: HeaderContext(
                keymap: .standard, home: try WorkingDirectory(path: "/Users/s"), now: now, texts: .spanish))
    }

    @Test func waitingHeaderSaysForHowLong() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(try agentPane(.stop, at: start), now: start.addingTimeInterval(125))

        #expect(content.status == .waiting)
        #expect(content.detail == HeaderDetail(text: "te espera · 2m", tone: .waiting))
    }

    @Test func failedHeaderSaysErrorAndHowLong() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(try agentPane(.stopFailure, at: start), now: start.addingTimeInterval(180))

        #expect(content.detail == HeaderDetail(text: "error · 3m", tone: .failed))
    }

    @Test func workingHeaderShowsTheSessionLifetime() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(try agentPane(.userPromptSubmit, at: start), now: start.addingTimeInterval(4320))

        #expect(content.status == .working)
        #expect(content.detail == HeaderDetail(text: "1h 12m", tone: .secondary))
    }

    @Test func stoppedAgentHasNoDetail() throws {
        let content = try header(try agentPane(.sessionEnd, at: .now), now: .now)

        #expect(content.status == .stopped)
        #expect(content.detail == nil)
    }

    @Test func countersNameEachStateAndSkipZeros() {
        #expect(
            StripCounter.counters(AgentCounts(working: 2, waiting: 1, failed: 0), texts: .spanish)
                == [
                    StripCounter(kind: .working, text: "2 trabajando"),
                    StripCounter(kind: .waiting, text: "1 te espera"),
                ])
        #expect(
            StripCounter.counters(AgentCounts(working: 0, waiting: 0, failed: 3), texts: .spanish) == [
                StripCounter(kind: .failed, text: "3 error")
            ])
        #expect(StripCounter.counters(AgentCounts(working: 0, waiting: 0, failed: 0), texts: .spanish).isEmpty)
    }

    // MARK: - Observatory details (F3)

    private func header(_ pane: Pane, now: Date, details: [String: PaneAgentDetail]) throws -> PaneHeaderContent {
        var context = HeaderContext(
            keymap: .standard, home: try WorkingDirectory(path: "/Users/s"), now: now, texts: .spanish)
        context.agentDetails = details
        return PaneHeaderContent(pane, index: 1, context: context)
    }

    @Test func headerDirectoryGainsModelFamily() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(
            try agentPane(.userPromptSubmit, at: start), now: start,
            details: ["s1": PaneAgentDetail(family: "opus", context: .percent(41))])

        #expect(content.directory == "~/dev/web · opus")
    }

    @Test func workingHeaderShowsContext() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(
            try agentPane(.userPromptSubmit, at: start), now: start.addingTimeInterval(4_320),
            details: ["s1": PaneAgentDetail(family: "opus", context: .percent(41))])

        #expect(content.context == .percent(41))
        #expect(content.detail == HeaderDetail(text: "1h 12m", tone: .secondary))
    }

    @Test func waitingHeaderHidesContext() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(
            try agentPane(.stop, at: start), now: start,
            details: ["s1": PaneAgentDetail(family: "sonnet", context: .percent(63))])

        #expect(content.context == nil)
        #expect(content.directory == "~/dev/web · sonnet")
    }

    @Test func unknownContextIsNotShown() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try header(
            try agentPane(.userPromptSubmit, at: start), now: start,
            details: ["s1": PaneAgentDetail(family: nil, context: .unavailable)])

        #expect(content.context == nil)
        #expect(content.directory == "~/dev/web")
    }

    @Test func headerWithoutDetailsIsUnchanged() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/s/dev/web"))

        let content = try header(
            pane, now: .now, details: ["s1": PaneAgentDetail(family: "opus", context: .percent(1))])

        #expect(content.directory == "~/dev/web")
        #expect(content.context == nil)
    }

    @Test func paneAgentsCarryTheWorkspaceLabel() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let pane = try agentPane(.userPromptSubmit, at: start)
        let root = try WorkingDirectory(path: "/Users/s/dev")
        let set = WorkspaceSet(
            first: Workspace.empty(name: "rizaria", rootDirectory: root, layout: DwindleLayout()).adding(pane))

        let agents = PaneAgent.all(in: set)

        #expect(agents.map(\.label) == ["rizaria/web"])
        #expect(agents.map(\.session.sessionID) == ["s1"])
        #expect(agents.map(\.pane) == [pane.id])
    }
}
