import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("ResumeListing")
struct ResumeListingTests {
    private let home = SessionFixtures.directory("/Users/s")
    private let harnesses = HarnessRegistry([FakeHarnessAdapter()])

    private func pane(
        _ path: String = "/Users/s/dev/solen", process: String? = "zsh", lines: Int = 0, commands: Int = 0,
        relaunch: [String]? = nil, agent: AgentSnapshot? = nil
    ) -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(), workingDirectory: path, title: nil, processName: process, scrollbackLines: lines,
            commandCount: commands, relaunch: relaunch.map(RelaunchCommand.init(arguments:)), agent: agent)
    }

    private func rows(_ panes: [PaneSnapshot], layout: String = "dwindle") -> ResumeWorkspace? {
        let workspace = WorkspaceSnapshot(
            name: "solen", rootDirectory: "/Users/s/dev/solen", layout: layout, tree: nil, focusedIndex: 0,
            panes: panes)
        return ResumeListing.workspaces(
            in: SessionSnapshot(version: 1, savedAt: .now, workspaces: [workspace], activeIndex: 0), home: home,
            harnesses: harnesses
        ).first
    }

    @Test func workspaceHeaderNamesLayoutAndPaneCount() {
        let listed = rows([pane(), pane()], layout: "columns")

        #expect(listed?.name == "solen")
        #expect(listed?.summary == "Columnas · 2 paneles")
    }

    @Test func onePaneIsSingular() {
        #expect(rows([pane()])?.summary == "Dwindle · 1 panel")
    }

    @Test func shellRowShowsDirectoryLinesAndCommands() {
        let row = rows([pane(lines: 1240, commands: 38)])?.rows.first

        #expect(row?.tag == ResumeTag(text: "zsh", kind: .program))
        #expect(row?.title == "~/dev/solen")
        #expect(row?.detail == "1.240 líneas · 38 comandos")
        #expect(row?.code == "scrollback")
        #expect(row?.isFinished == false)
    }

    @Test func shellWithoutSavedLinesHasNoScrollbackCode() {
        let row = rows([pane(lines: 0, commands: 1)])?.rows.first

        #expect(row?.detail == "1 comando")
        #expect(row?.code == nil)
    }

    @Test func agentRowShowsHarnessTitleAndShortResumeCommand() {
        let agent = AgentSnapshot(
            harness: .claude, sessionID: "7f3a9c2e-1111", title: "Agendar recordatorios", lastState: .waiting)

        let row = rows([pane(process: "claude", agent: agent)])?.rows.first

        #expect(row?.tag == ResumeTag(text: "Fake", kind: .agent))
        #expect(row?.title == "Agendar recordatorios")
        #expect(row?.code == "fake --resume 7f3a…")
    }

    @Test func agentWithoutTitleShowsItsDirectory() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: nil, lastState: .working)

        #expect(rows([pane(process: "claude", agent: agent)])?.rows.first?.title == "~/dev/solen")
    }

    @Test func finishedAgentIsMarked() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "c41e", title: "Pagos", lastState: .stopped)

        let row = rows([pane(process: "claude", agent: agent)])?.rows.first

        #expect(row?.isFinished == true)
        #expect(row?.detail == "terminada")
    }

    @Test func relaunchRowShowsTheProgramAndItsCommand() {
        let row = rows([pane(process: "node", relaunch: ["pnpm", "dev"])])?.rows.first

        #expect(row?.tag == ResumeTag(text: "node", kind: .program))
        #expect(row?.code == "pnpm dev")
    }

    @Test func paneWithoutAKnownProcessIsTaggedShell() {
        #expect(rows([pane(process: nil)])?.rows.first?.tag == ResumeTag(text: "shell", kind: .program))
    }

    @Test func workspaceStatusIsTheMostUrgentAgent() {
        let waiting = AgentSnapshot(harness: .claude, sessionID: "a", title: nil, lastState: .waiting)
        let working = AgentSnapshot(harness: .claude, sessionID: "b", title: nil, lastState: .working)

        #expect(rows([pane(agent: working), pane(agent: waiting)])?.status == .waiting)
        #expect(rows([pane()])?.status == nil)
    }

    @Test(arguments: [(0, "0"), (999, "999"), (1240, "1.240"), (1_234_567, "1.234.567")])
    func thousandsUseADot(value: Int, expected: String) {
        #expect(ResumeListing.grouped(value) == expected)
    }
}

@Suite("ResumeListing · windows")
struct ResumeListingWindowsTests {
    private let home = SessionFixtures.directory("/Users/s")
    private let harnesses = HarnessRegistry([FakeHarnessAdapter()])

    private func window(_ names: [String]) -> WindowSnapshot {
        WindowSnapshot(
            frame: nil, isFullScreen: false,
            workspaces: names.map {
                WorkspaceSnapshot(
                    name: $0, rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: nil, panes: [])
            },
            activeIndex: 0)
    }

    private func listing(_ windows: [WindowSnapshot]) -> [ResumeWindow] {
        ResumeListing.windows(
            in: SessionSnapshot(version: 2, savedAt: .now, windows: windows, frontIndex: 0), home: home,
            harnesses: harnesses)
    }

    @Test func listingGroupsByWindowWhenTwoOrMore() {
        let windows = listing([window(["solen", "billi"]), window(["smalti"])])

        #expect(windows.map(\.title) == ["Ventana 1 · 2 workspaces", "Ventana 2 · 1 workspace"])
        #expect(windows.map { $0.workspaces.map(\.name) } == [["solen", "billi"], ["smalti"]])
    }

    @Test func listingFlatWithOneWindow() {
        let windows = listing([window(["solen", "billi"])])

        #expect(windows.count == 1)
        #expect(windows[0].title == nil)
    }
}
