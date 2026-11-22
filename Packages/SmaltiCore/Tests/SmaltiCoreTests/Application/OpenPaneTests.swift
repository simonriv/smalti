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
        let environment = ChildEnvironment.smalti(version: "1.2")
        let open = OpenPane(engine: engine, environment: environment)

        _ = try open.execute(request(roomy), in: &set)

        #expect(engine.openedSpecs.first?.environment == ["SMALTI": "1", "SMALTI_VERSION": "1.2"])
    }

    @Test mutating func openKeepsSpecEnvironmentAndAddsSmalti() throws {
        let environment = ["EDITOR": "vim"].merging(ChildEnvironment.smalti(version: "1")) { $1 }
        let open = OpenPane(engine: engine, environment: environment)

        _ = try open.execute(request(roomy), in: &set)

        #expect(engine.openedSpecs.first?.environment == ["EDITOR": "vim", "SMALTI": "1", "SMALTI_VERSION": "1"])
    }

    @Test mutating func openAddsThePaneWithTheEngineId() throws {
        let open = OpenPane(engine: engine, environment: [:])

        let id = try open.execute(request(roomy), in: &set)

        #expect(set.active.panes.map(\.id) == [id])
        #expect(set.active.focusedPane == id)
        #expect(engine.openedSpecs == [TerminalSessionSpec(workingDirectory: tmp, command: .loginShell)])
    }

    @Test mutating func openUsesFocusedPaneDirectory() throws {
        let elsewhere = try WorkingDirectory(path: "/var")
        let first = Pane(id: PaneID(), workingDirectory: elsewhere)
        set = set.updating(set.activeID) { $0.adding(first) }

        _ = try OpenPane(engine: engine, environment: [:]).execute(request(roomy), in: &set)

        #expect(engine.openedSpecs.first?.workingDirectory == elsewhere)
    }

    @Test mutating func openRefusesWhenMinimumWouldBreak() throws {
        let open = OpenPane(engine: engine, environment: [:])
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
            try OpenPane(engine: engine, environment: [:]).execute(request(roomy), in: &set)
        }
        #expect(set == before)
    }
}
