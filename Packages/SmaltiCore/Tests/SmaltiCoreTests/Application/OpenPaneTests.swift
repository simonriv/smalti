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

        #expect(engine.openedSpecs.first?.environment == ["SMALTI": "1", "SMALTI_VERSION": "1.2"])
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

    @Test mutating func openAddsThePaneWithTheEngineId() throws {
        let open = OpenPane(engine: engine, version: "1")

        let id = try open.execute(request(roomy), in: &set)

        #expect(set.active.panes.map(\.id) == [id])
        #expect(set.active.focusedPane == id)
        let spec = TerminalSessionSpec(
            workingDirectory: tmp, command: .loginShell, environment: ChildEnvironment.smalti(version: "1"))
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
}
