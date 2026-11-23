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

        let header = PaneHeaderContent(pane, index: 3, context: HeaderContext(keymap: .standard, home: home, now: .now))

        #expect(header == PaneHeaderContent(process: "claude", directory: "~/dev/xolken", status: nil, detail: nil, shortcut: "⌘3"))
    }

    @Test func headerWithoutIndexHasNoShortcut() throws {
        let pane = Pane(id: PaneID(), workingDirectory: home).applying(.titleChanged("vim notes.md"))

        let header = PaneHeaderContent(pane, index: nil, context: HeaderContext(keymap: .standard, home: home, now: .now))

        #expect(header == PaneHeaderContent(process: "vim notes.md", directory: "~", status: nil, detail: nil, shortcut: ""))
    }

    // MARK: - Agent state (F2)

    private func agentPane(_ hook: AgentHook, at start: Date) throws -> Pane {
        let base = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/s/dev/web"))
        return base.applying(AgentEvent(pane: base.id, hook: hook, at: start, sessionID: "s1", prompt: "x", message: "m")).0
    }

    private func header(_ pane: Pane, now: Date) throws -> PaneHeaderContent {
        PaneHeaderContent(
            pane, index: 1, context: HeaderContext(keymap: .standard, home: try WorkingDirectory(path: "/Users/s"), now: now))
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
            StripCounter.counters(AgentCounts(working: 2, waiting: 1, failed: 0))
                == [StripCounter(kind: .working, text: "2 trabajando"), StripCounter(kind: .waiting, text: "1 te espera")])
        #expect(StripCounter.counters(AgentCounts(working: 0, waiting: 0, failed: 3)) == [StripCounter(kind: .failed, text: "3 error")])
        #expect(StripCounter.counters(AgentCounts(working: 0, waiting: 0, failed: 0)).isEmpty)
    }
}
