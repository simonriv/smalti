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
}
