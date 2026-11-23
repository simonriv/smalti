import Foundation
import SmaltiCore
import Testing

@Suite("SessionSnapshot")
struct SessionSnapshotTests {
    private let root: WorkingDirectory
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        root = try WorkingDirectory(path: "/Users/s/dev/solen")
    }

    private func workspace(_ name: String, panes: [Pane]) -> Workspace {
        panes.reduce(Workspace.empty(name: name, rootDirectory: root, layout: DwindleLayout())) { $0.adding($1) }
    }

    private func pane(in path: String = "/Users/s/dev/solen") throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: path))
    }

    @Test(arguments: [0, 1, 9])
    func captureKeepsOrderLayoutFocusAndDirectories(paneCount: Int) throws {
        let panes = try (0..<paneCount).map { try pane(in: "/tmp/p\($0)") }
        let first = workspace("solen", panes: panes)
        let set = WorkspaceSet(first: first).adding(workspace("rizaria", panes: [])).activating(first.id)

        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        #expect(snapshot.version == SessionSnapshot.formatVersion)
        #expect(snapshot.savedAt == now)
        #expect(snapshot.workspaces.map(\.name) == ["solen", "rizaria"])
        #expect(snapshot.activeIndex == 0)
        let saved = snapshot.workspaces[0]
        #expect(saved.layout == "dwindle")
        #expect(saved.panes.map(\.workingDirectory) == (0..<paneCount).map { "/tmp/p\($0)" })
        #expect(saved.panes.map(\.id) == panes.map(\.id.rawValue))
        #expect(saved.focusedIndex == (paneCount == 0 ? nil : paneCount - 1))
        #expect((saved.tree == nil) == (paneCount == 0))
    }

    @Test func captureRecordsScrollbackLineCounts() throws {
        let shell = try pane()
        let set = WorkspaceSet(first: workspace("solen", panes: [shell]))

        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [shell.id: 1240], at: now)

        #expect(snapshot.workspaces[0].panes[0].scrollbackLines == 1240)
    }

    @Test func captureRecordsRelaunchOnlyForNonShellNonAgent() throws {
        let server = try pane().applying(
            .foregroundProcessChanged(ForegroundProcess(name: "node", commandLine: ["pnpm", "dev"])))
        let shell = try pane().applying(
            .foregroundProcessChanged(ForegroundProcess(name: "zsh", commandLine: ["-zsh"])))
        let set = WorkspaceSet(first: workspace("solen", panes: [server, shell]))

        let panes = SessionSnapshot.capture(set, scrollbackLines: [:], at: now).workspaces[0].panes

        #expect(panes[0].relaunch == RelaunchCommand(arguments: ["pnpm", "dev"]))
        #expect(panes[1].relaunch == nil)
    }

    @Test func captureKeepsAgentSnapshot() throws {
        let session = AgentSession(
            harness: .claude, sessionID: "7f3a9c", title: "Agendar recordatorios", state: .working, startedAt: now)
        let agentPane = try pane()
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "claude", commandLine: ["claude"])))
            .attaching(session)
        let set = WorkspaceSet(first: workspace("solen", panes: [agentPane]))

        let saved = SessionSnapshot.capture(set, scrollbackLines: [:], at: now).workspaces[0].panes[0]

        #expect(
            saved.agent
                == AgentSnapshot(
                    harness: .claude, sessionID: "7f3a9c", title: "Agendar recordatorios", lastState: .working))
        #expect(saved.relaunch == nil)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let set = WorkspaceSet(first: workspace("solen", panes: [try pane(), try pane()]))
        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        let data = try JSONEncoder().encode(snapshot)

        #expect(try JSONDecoder().decode(SessionSnapshot.self, from: data) == snapshot)
    }

    @Test func relaunchDisplayTextEscapesArguments() {
        let command = RelaunchCommand(arguments: ["pnpm", "--filter", "my app", "dev"])

        #expect(command.displayText == "pnpm --filter 'my app' dev")
    }

    @Test(arguments: ["zsh", "-zsh", "bash", "fish", "sh"])
    func knownShellsAreShells(name: String) {
        #expect(ShellNames.contains(name))
    }

    @Test func otherProcessesAreNotShells() {
        #expect(!ShellNames.contains("claude"))
        #expect(!ShellNames.contains("zshrc"))
    }
}
