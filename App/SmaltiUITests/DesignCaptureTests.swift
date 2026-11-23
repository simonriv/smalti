import XCTest

/// C18: window captures to lay over the boards (Reanudar.dc.html, Main.dc.html). They run only on demand:
/// `TEST_RUNNER_SMALTI_CAPTURE=1 scripts/test-ui.sh DesignCaptureTests`; PNGs land in the runner's temporary
/// directory, `smalti-captures/`.
final class DesignCaptureTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var captures: URL { FileManager.default.temporaryDirectory.appending(path: "smalti-captures") }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_CAPTURE"] == "1", "captures run on demand")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
    }

    func testCaptureResumeScreen() throws {
        let app = XCUIApplication.isolatedSmalti()
        // The runner lives in a container; the app abbreviates against the real home.
        let home = "/Users/\(NSUserName())"
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "\(home)/dev/solen", layout: "dwindle",
                    panes: [
                        .init(
                            directory: "\(home)/dev/solen", agentSessionID: "7f3a9c2e-1111-4b7a-9c11-2f6e5d4c3b2a",
                            title: "Agendar recordatorios al crear eventos", process: "claude"),
                        .init(directory: "\(home)/dev/solen", process: "zsh", lines: 1240, commands: 38),
                        .init(directory: "\(home)/dev/solen", relaunch: ["nvim", "+42"], process: "nvim"),
                    ]),
                .init(
                    name: "rizaria", root: "\(home)/dev/rizaria", layout: "columns",
                    panes: [
                        .init(
                            directory: "\(home)/dev/rizaria/web",
                            agentSessionID: "01980000-2222-4b7a-9c11-2f6e5d4c3b2a",
                            title: "Onboarding con preferencias de usuario", process: "claude"),
                        .init(directory: "\(home)/dev/rizaria", process: "zsh", lines: 320, commands: 12),
                    ]),
            ], alwaysRestore: false, in: app)
        self.app = app
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))

        try save(app.windows.firstMatch.screenshot(), as: "c18-restore.png")
    }

    /// F3 C12: the observatory over the bundled fixture, to lay over Observatorio.dc.html.
    func testCaptureObservatory() throws {
        let app = XCUIApplication.isolatedSmalti()
        try app.installObservatoryFixture(
            from: Bundle(for: Self.self), newestFirst: ["projects/-fixture-work-x/tools-session.jsonl"])
        launch(app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3)

        try save(app.windows.firstMatch.screenshot(), as: "f3-observatory.png")
    }

    /// F3 C12: the status bar's figures and a working Claude header with its model and "ctx N%".
    func testCaptureStatusAndHeader() throws {
        let app = XCUIApplication.isolatedSmalti()
        try app.installObservatoryFixture(from: Bundle(for: Self.self))
        launch(app)
        let session = "401a63e1-c076-45fe-9f09-432da1c8cfa6"
        app.run(#"printf '{"session_id":"\#(session)","source":"startup"}' | "$SMALTI_CLI" event SessionStart; clear"#)
        app.run(#"printf '{"session_id":"\#(session)","prompt":"x"}' | "$SMALTI_CLI" event UserPromptSubmit; clear"#)
        XCTAssertTrue(app.element("smalti.paneContext").waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)

        try save(app.windows.firstMatch.screenshot(), as: "f3-status-header.png")
    }

    /// F3 Task 0: the palette after arrowing to its last row (the selection used to sit below the clipped edge).
    func testCapturePaletteLastRowSelected() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        openPalette()
        let rows = app.elements("smalti.paletteRow").count
        for _ in 1..<rows { app.typeKey(.downArrow, modifierFlags: []) }

        try save(app.windows.firstMatch.screenshot(), as: "palette-last-row.png")
    }

    func testCaptureAgentStatus() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 3)
        app.typeKey("1", modifierFlags: .command)
        app.run(
            #"printf '{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","prompt":"x"}' | "$SMALTI_CLI" event UserPromptSubmit; clear"#
        )
        app.typeKey("2", modifierFlags: .command)
        app.run(#"printf '{"session_id":"9f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"}' | "$SMALTI_CLI" event Stop; clear"#)
        app.typeKey("1", modifierFlags: .command)
        let counter = app.element("smalti.counter.waiting")
        XCTAssertTrue(counter.waitForExistence(timeout: 5))

        try save(app.windows.firstMatch.screenshot(), as: "c18-status.png")
    }

    private func save(_ screenshot: XCUIScreenshot, as name: String) throws {
        try screenshot.pngRepresentation.write(to: captures.appending(path: name))
    }
}
