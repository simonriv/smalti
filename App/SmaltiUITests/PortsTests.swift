import XCTest

/// F8 (C7, C3): the ports view (⌘⇧U) with listeners started in the test's own pane, and forcing a quit only after
/// SIGTERM failed and the person confirmed. `-SmaltiStopGraceSeconds 1` shortens the wait.
final class PortsTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }
    private var listener: PaneListener!  // Created per test.
    private var started: (pid: Int32, port: Int)?

    override func tearDown() async throws {
        listener?.end(started?.pid)
        try await super.tearDown()
    }

    private func launchWithListener(ignoringTerm: Bool = false) -> (pid: Int32, port: Int) {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiStopGraceSeconds", "1"]
        launch(app)
        do {
            listener = try PaneListener(outputFile: outputFile, ignoringTerm: ignoringTerm)
        } catch {
            XCTFail("listener script: \(error)")
        }
        let listening = start(listener)
        started = listening
        openPorts()
        filter(String(listening.port))
        XCTAssertTrue(row(listening).waitForExistence(timeout: 10))
        return listening
    }

    private func row(_ listening: (pid: Int32, port: Int)) -> XCUIElement {
        app.element("smalti.ports.row.\(listening.pid).tcp.\(listening.port)")
    }

    func testListenerShowsPortProtocolScopeAndPane() {
        let listening = launchWithListener()

        let label = row(listening).label
        XCTAssertTrue(label.hasPrefix("\(listening.port) · TCP · solo local"), label)
        XCTAssertTrue(label.contains(" · 1"), label)
        let detail = app.element("smalti.processes.detail").value as? String ?? ""
        XCTAssertTrue(detail.contains("127.0.0.1"), detail)
    }

    func testForceOnlyAfterTermFailsAndConfirmation() {
        let listening = launchWithListener(ignoringTerm: true)

        app.typeKey(.delete, modifierFlags: .command)
        waitUntil { self.notice().contains("que termine") }
        waitUntil { self.row(listening).label.contains("sin responder") }
        XCTAssertTrue(PaneListener.isAlive(listening.pid))

        app.typeKey(.delete, modifierFlags: .command)
        let card = app.element("smalti.processes.confirm")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.hasPrefix("¿Forzar el cierre de "), card.label)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(PaneListener.isAlive(listening.pid))

        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])

        waitUntil { !PaneListener.isAlive(listening.pid) }
        XCTAssertTrue(row(listening).waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.element("smalti.processes").exists)
    }

    func testEnterGoesToThePane() {
        _ = launchWithListener()

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.processes").waitForNonExistence(timeout: 5))
    }

    func testPortsViewCountsTheListener() {
        _ = launchWithListener()

        let summary = app.element("smalti.ports.summary").value as? String ?? ""
        XCTAssertTrue(summary.hasPrefix("1 puerto"), summary)
    }
}
