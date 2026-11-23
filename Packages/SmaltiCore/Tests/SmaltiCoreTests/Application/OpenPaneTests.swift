import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("OpenPane")
struct OpenPaneTests {
    private let engine = FakeTerminalEngine()
    private let tmp: WorkingDirectory
    private let roomy = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 1000, height: 600))
    private let cramped = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 300, height: 150))
    private var set: WorkspaceSet

    init() throws {
        tmp = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: tmp, layout: DwindleLayout()))
    }

    private func request(_ geometry: LayoutGeometry) -> OpenPaneRequest {
        OpenPaneRequest(shell: .loginShell, geometry: geometry)
    }

    @Test mutating func openPassesSmaltiEnvironment() throws {
        let open = OpenPane(engine: engine, version: "1.2")

        _ = try open.execute(request(roomy), in: &set)

        let environment = engine.openedSpecs.first?.environment
        #expect(environment?["SMALTI"] == "1")
        #expect(environment?["SMALTI_VERSION"] == "1.2")
    }

    @Test mutating func openKeepsSpecEnvironmentAndAddsSmalti() throws {
        let open = OpenPane(
            engine: engine, version: "1", environment: ["EDITOR": "vim", "SMALTI": "0", "SMALTI_VERSION": "old"])

        _ = try open.execute(request(roomy), in: &set)

        let environment = engine.openedSpecs.first?.environment
        #expect(environment?["EDITOR"] == "vim")
        #expect(environment?["SMALTI"] == "1")
        #expect(environment?["SMALTI_VERSION"] == "1")
    }

    @Test mutating func openAddsThePaneItOpened() throws {
        let open = OpenPane(engine: engine, version: "1")

        let id = try open.execute(request(roomy), in: &set)

        #expect(set.active.panes.map(\.id) == [id])
        #expect(set.active.focusedPane == id)
        let spec = TerminalSessionSpec(
            workingDirectory: tmp, command: .loginShell, environment: PaneEnvironment(version: "1").variables(for: id))
        #expect(engine.openedSpecs == [spec])
    }

    @Test mutating func openUsesFocusedPaneDirectory() throws {
        let elsewhere = try WorkingDirectory(path: "/var")
        let first = Pane(id: PaneID(), workingDirectory: elsewhere)
        set = set.updating(set.activeID) { $0.adding(first) }

        _ = try OpenPane(engine: engine, version: "1").execute(request(roomy), in: &set)

        #expect(engine.openedSpecs.first?.workingDirectory == elsewhere)
    }

    @Test mutating func openRefusesWhenMinimumWouldBreak() throws {
        let open = OpenPane(engine: engine, version: "1")
        _ = try open.execute(request(cramped), in: &set)
        let before = set

        #expect(throws: OpenPaneError.paneTooSmall(minimum: LayoutGeometry.standardMinimumPaneSize)) {
            try open.execute(request(cramped), in: &set)
        }
        #expect(engine.openedSpecs.count == 1)
        #expect(set == before)
    }

    @Test mutating func openPropagatesEngineFailure() {
        let failure = TerminalEngineError.surfaceCreationFailed(workingDirectory: "/tmp", reason: "x")
        engine.failure = failure
        let before = set

        #expect(throws: OpenPaneError.engine(failure)) {
            try OpenPane(engine: engine, version: "1").execute(request(roomy), in: &set)
        }
        #expect(set == before)
    }

    @Test mutating func openGivesTheEngineTheNewPaneID() throws {
        let id = try OpenPane(engine: engine, version: "1").execute(request(roomy), in: &set)

        #expect(engine.openedIDs == [id])
        #expect(engine.openedSpecs.first?.environment["SMALTI_PANE_ID"] == id.description)
    }

    @Test mutating func openPassesHistoryFileWhenFilesAreKnown() throws {
        let files = PaneFileLocator(stateDirectory: URL(filePath: "/state"))
        let open = OpenPane(engine: engine, environment: PaneEnvironment(version: "1", files: files))

        let id = try open.execute(request(roomy), in: &set)

        #expect(engine.openedSpecs.first?.environment["SMALTI_HISTORY_FILE"] == "/state/history/\(id).zsh_history")
    }

    @Test func environmentCarriesSocketCliAndPath() {
        let ipc = IPCEndpoints(
            socket: URL(filePath: "/state/smalti.sock"), cli: URL(filePath: "/App.app/Contents/Resources/bin/smalti"),
            inheritedPath: "/usr/bin:/bin")
        let environment = PaneEnvironment(version: "1", ipc: ipc).variables(for: PaneID())

        #expect(environment["SMALTI_SOCKET"] == "/state/smalti.sock")
        #expect(environment["SMALTI_CLI"] == "/App.app/Contents/Resources/bin/smalti")
        #expect(environment["PATH"] == "/App.app/Contents/Resources/bin:/usr/bin:/bin")
    }

    @Test func exportsInputSocket() {
        let ipc = IPCEndpoints(
            socket: URL(filePath: "/state/smalti.sock"), cli: URL(filePath: "/bin/smalti"), inheritedPath: "/usr/bin",
            inputSocket: URL(filePath: "/state/input.sock"))

        #expect(
            PaneEnvironment(version: "1", ipc: ipc).variables(for: PaneID())["SMALTI_INPUT_SOCKET"]
                == "/state/input.sock")
    }

    @Test func withoutInputSocketThereIsNoInputVariable() {
        let ipc = IPCEndpoints(
            socket: URL(filePath: "/s.sock"), cli: URL(filePath: "/bin/smalti"), inheritedPath: "/usr/bin")

        #expect(PaneEnvironment(version: "1", ipc: ipc).variables(for: PaneID())["SMALTI_INPUT_SOCKET"] == nil)
    }

    @Test func withoutIPCThereIsNoSocketOrCli() {
        let environment = PaneEnvironment(version: "1").variables(for: PaneID())

        #expect(environment["SMALTI_SOCKET"] == nil)
        #expect(environment["SMALTI_CLI"] == nil)
        #expect(environment["PATH"] == nil)
    }

    @Test mutating func aDeletedCurrentDirectoryFallsBackToHome() throws {
        engine.failingDirectories = ["/tmp"]
        let home = try WorkingDirectory(path: "/Users/s")
        let request = OpenPaneRequest(shell: .loginShell, geometry: roomy, home: home)

        let id = try OpenPane(engine: engine, version: "1").execute(request, in: &set)

        #expect(engine.openedSpecs.map(\.workingDirectory) == [home])
        #expect(set.active.panes.first { $0.id == id }?.workingDirectory == home)
    }
}
