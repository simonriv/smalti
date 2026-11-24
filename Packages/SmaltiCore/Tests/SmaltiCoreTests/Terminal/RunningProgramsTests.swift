import Foundation
import SmaltiCoreTestSupport
import Testing

@testable import SmaltiCore

/// Final review (minor 2): hidden panes stop watching their foreground process (R7), so closing asks the engine
/// again what runs in each pane before deciding.
@MainActor
struct RunningProgramsTests {
    private let engine = FakeTerminalEngine()

    private func pane(running name: String?) -> Pane {
        let pane = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        return name.map { pane.applying(.foregroundProcessChanged(ForegroundProcess(name: $0))) } ?? pane
    }

    @Test func aProgramThatEndedWhileHiddenIsNotBusy() {
        let stale = pane(running: "sleep")
        engine.foregroundProcesses[stale.id] = ForegroundProcess(name: "zsh")

        #expect(RunningPrograms(engine: engine).busy(in: [stale]).isEmpty)
    }

    @Test func aProgramThatStartedWhileHiddenIsBusyWithItsCommandLine() {
        let stale = pane(running: nil)
        engine.foregroundProcesses[stale.id] = ForegroundProcess(name: "sleep", commandLine: ["sleep", "60"])

        let busy = RunningPrograms(engine: engine).busy(in: [stale])

        #expect(busy == [BusyPane(pane: stale.id, command: "sleep 60")])
    }

    @Test func aPaneTheEngineCannotReadKeepsWhatWasLastReported() {
        let known = pane(running: "vim")

        #expect(RunningPrograms(engine: engine).busy(in: [known]).map(\.pane) == [known.id])
    }

    @Test func everyWindowIsAskedAgain() throws {
        let front = pane(running: nil)
        let hidden = pane(running: nil)
        engine.foregroundProcesses[hidden.id] = ForegroundProcess(name: "htop")
        let windows = WindowSet(first: try window(front)).opening(try window(hidden))

        #expect(RunningPrograms(engine: engine).busy(in: windows).map(\.pane) == [hidden.id])
    }

    private func window(_ pane: Pane) throws -> WindowState {
        let root = try WorkingDirectory(path: "/tmp")
        let workspace = Workspace.empty(name: "w", rootDirectory: root, layout: DwindleLayout()).adding(pane)
        return WindowState(id: WindowID(), workspaces: WorkspaceSet(first: workspace), frame: nil, isFullScreen: false)
    }
}
