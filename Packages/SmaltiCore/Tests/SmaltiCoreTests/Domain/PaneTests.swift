import SmaltiCore
import Testing

@Suite("Pane")
struct PaneTests {
    private let home: WorkingDirectory
    private let pane: Pane

    init() throws {
        home = try WorkingDirectory(path: "/Users/simon")
        pane = Pane(id: PaneID(), workingDirectory: home)
    }

    @Test func newPaneIsRunningWithoutTitle() {
        #expect(pane.isRunning)
        #expect(pane.title == nil)
        #expect(pane.lastCommand == nil)
    }

    @Test func titleChangedUpdatesTitle() {
        #expect(pane.applying(.titleChanged("claude")).title == "claude")
    }

    @Test func workingDirectoryChangedUpdatesDirectory() throws {
        let tmp = try WorkingDirectory(path: "/tmp")

        #expect(pane.applying(.workingDirectoryChanged(tmp)).workingDirectory == tmp)
    }

    @Test func commandFinishedRecordsOutcome() {
        let updated = pane.applying(.commandFinished(exitCode: 1, duration: .milliseconds(400)))

        #expect(updated.lastCommand == CommandOutcome(exitCode: 1, duration: .milliseconds(400)))
    }

    @Test func exitedStopsThePane() {
        #expect(pane.applying(.exited(code: 0)).isRunning == false)
    }

    @Test func bellLeavesPaneUnchanged() {
        #expect(pane.applying(.bell) == pane)
    }

    @Test func paneRecordsForegroundProcess() {
        #expect(pane.applying(.foregroundProcessChanged(ForegroundProcess(name: "claude"))).processName == "claude")
    }

    @Test func closeRequestedLeavesPaneUnchanged() {
        #expect(pane.applying(.closeRequested) == pane)
    }

    @Test func headerNamePrefersProcessThenTitleThenEmpty() {
        let titled = pane.applying(.titleChanged("~/dev"))

        #expect(pane.headerName == "")
        #expect(titled.headerName == "~/dev")
        #expect(titled.applying(.foregroundProcessChanged(ForegroundProcess(name: "vim"))).headerName == "vim")
    }

    @Test func commandFinishedCountsCommands() {
        let finished = TerminalEvent.commandFinished(exitCode: 0, duration: .seconds(1))

        #expect(pane.applying(finished).applying(finished).commandCount == 2)
    }

    @Test func foregroundProcessKeepsItsCommandLine() {
        let event = TerminalEvent.foregroundProcessChanged(
            ForegroundProcess(name: "node", commandLine: ["pnpm", "dev"]))

        #expect(pane.applying(event).foregroundCommandLine == ["pnpm", "dev"])
    }

    @Test func newPaneIsAtShell() {
        #expect(pane.isAtShell)
    }

    @Test func paneRunningAProgramIsNotAtShell() {
        #expect(!pane.applying(.foregroundProcessChanged(ForegroundProcess(name: "nvim"))).isAtShell)
    }
}
