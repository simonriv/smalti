import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("OpenPane")
struct OpenPaneTests {
    private let engine = FakeTerminalEngine()
    private let tmp: WorkingDirectory

    init() throws {
        tmp = try WorkingDirectory(path: "/tmp")
    }

    @Test func opensLoginShellInRequestedDirectory() throws {
        let pane = try OpenPane(engine: engine).execute(.loginShell(in: tmp))

        #expect(engine.openedSpecs == [.loginShell(in: tmp)])
        #expect(pane.workingDirectory == tmp)
        #expect(pane.isRunning)
    }

    @Test func propagatesEngineFailure() {
        let failure = TerminalEngineError.surfaceCreationFailed(workingDirectory: "/tmp", reason: "x")
        engine.failure = failure

        #expect(throws: failure) {
            try OpenPane(engine: engine).execute(.loginShell(in: tmp))
        }
    }

    @Test func eventsReachSubscriber() async throws {
        let pane = try OpenPane(engine: engine).execute(.loginShell(in: tmp))
        let events = engine.events(for: pane.id)

        engine.emit(.titleChanged("zsh"), for: pane.id)

        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .titleChanged("zsh"))
    }
}
