import XCTest

/// F8 (C6): the processes view (⌘⇧M) with a listener started in the test's own pane: its row, pane and command, the
/// filter, the tree with the pane's shell protected, the order, lowering its priority, stopping it and ↵ to its pane.
final class ProcessesTests: SmaltiUITestCase {
    private var listener: PaneListener!  // Created per test in setUp.
    private var started: (pid: Int32, port: Int)?

    override func setUp() async throws {
        try await super.setUp()
        listener = try PaneListener(outputFile: outputFile)
    }

    override func tearDown() async throws {
        listener.end(started?.pid)
        try await super.tearDown()
    }

    private func row(_ pid: Int32) -> XCUIElement { app.element("smalti.processes.row.\(pid)") }

    /// Starts the listener and shows only it in the view.
    private func showListener() -> Int32 {
        started = start(listener)
        let pid = started?.pid ?? 0
        openProcesses()
        filter(String(pid))
        XCTAssertTrue(row(pid).waitForExistence(timeout: 10))
        return pid
    }

    func testListenerShowsWithItsPaneCommandAndDirectory() {
        let pid = showListener()

        XCTAssertTrue(row(pid).label.contains(" · 1"), row(pid).label)
        let detail = app.element("smalti.processes.detail")
        let value = detail.value as? String ?? ""
        XCTAssertTrue(value.contains(listener.name), value)
        XCTAssertTrue(value.contains("Directorio"), value)
        XCTAssertEqual(app.element("smalti.processes.filter").value as? String, String(pid))
    }

    func testFilterWithoutMatchSaysSo() {
        openProcesses()

        filter("zzzsinnada")

        XCTAssertTrue(app.element("smalti.processes.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(app.element("smalti.processes.empty").value as? String, "Nada coincide con «zzzsinnada»")
    }

    func testTreeShowsThePaneShellAsProtectedParent() {
        let pid = showListener()

        app.typeKey("t", modifierFlags: .command)

        XCTAssertEqual(app.element("smalti.processes.tree").value as? String, "on")
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'smalti.processes.row.'"))
        waitUntil { rows.count >= 2 }
        let shell = rows.element(boundBy: 0)
        XCTAssertTrue(shell.label.contains("zsh"), shell.label)
        XCTAssertNotEqual(shell.identifier, "smalti.processes.row.\(pid)")

        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.delete, modifierFlags: .command)

        waitUntil { self.notice().contains("es el shell del panel") }
        XCTAssertTrue(app.element("smalti.processes.protection").exists)
        XCTAssertTrue(PaneListener.isAlive(pid))
    }

    func testSortCyclesTheOrder() {
        openProcesses()
        XCTAssertEqual(app.element("smalti.processes.order").label, "CPU ↓")

        app.typeKey("s", modifierFlags: [.command, .shift])

        XCTAssertEqual(app.element("smalti.processes.order").label, "Memoria ↓")
    }

    func testLowerPriorityRaisesNiceOneStep() {
        let pid = showListener()

        app.typeKey(.downArrow, modifierFlags: [.command, .shift])

        waitUntil { PaneListener.nice(of: pid) == 5 }
        waitUntil { self.notice().contains("prioridad baja (5)") }
    }

    func testStopEndsAListenerThatQuits() {
        let pid = showListener()

        app.typeKey(.delete, modifierFlags: .command)

        waitUntil { !PaneListener.isAlive(pid) }
        XCTAssertTrue(row(pid).waitForNonExistence(timeout: 5))
    }

    func testEnterGoesToItsPaneAndEscapeClearsThenCloses() {
        let pid = showListener()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.element("smalti.processes.filter").value as? String, "")
        XCTAssertTrue(app.element("smalti.processes").exists)
        filter(String(pid))
        XCTAssertTrue(row(pid).waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.processes").waitForNonExistence(timeout: 5))
        XCTAssertTrue(PaneListener.isAlive(pid))
    }

    func testShortcutClosesAndPortsShortcutSwitches() {
        openProcesses()
        app.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertEqual(app.element("smalti.processes.mode.ports").value as? String, "selected")

        app.typeKey("u", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.element("smalti.processes").waitForNonExistence(timeout: 5))
    }

    func testPaletteOpensTheView() {
        openPalette()
        app.typeText("abrirprocesos")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.processes").waitForExistence(timeout: 5))
    }
}
