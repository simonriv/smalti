import XCTest

/// ⌘K palette (B7, Paleta.dc.html). Typing avoids spaces: XCUITest sends them as ⌃Space on this layout.
final class CommandPaletteTests: SmaltiUITestCase {
    func testPaletteFiltersLayoutsAndSwitches() {
        openPalette()

        app.typeText("col")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertFalse(app.element("smalti.palette").exists)
        expect(app.element("smalti.statusBar"), valueEndsWith: "· columnas")
    }

    func testEscapeClosesPalette() {
        openPalette()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    func testCommandKTogglesThePalette() {
        openPalette()

        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    /// ⌘A works in the field: "x" replaces the selected name, ⌘A selects it again, "solen" replaces it.
    func testRenameWorkspaceFromPalette() {
        openPalette()
        app.typeText("renombrar")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("x")
        app.typeKey("a", modifierFlags: .command)

        app.typeText("solen")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.element("smalti.workspace").label, "solen")
    }

    /// ⌘Z undoes typing in the field: "col" then ⌘Z leaves no query, so every group shows again.
    func testCommandZUndoesTypingInTheField() {
        openPalette()
        app.typeText("col")

        app.typeKey("z", modifierFlags: .command)

        expect(app.element("smalti.paletteField"), value: "")
    }

    func testShiftCommandZRedoesTypingInTheField() {
        openPalette()
        app.typeText("col")
        app.typeKey("z", modifierFlags: .command)

        app.typeKey("z", modifierFlags: [.command, .shift])

        expect(app.element("smalti.paletteField"), value: "col")
    }

    func testEscapeCancelsRename() {
        let original = app.element("smalti.workspace").label
        openPalette()
        app.typeText("renombrar")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("zzz")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.element("smalti.workspace").label, original)
    }

    func testClickOutsideClosesThePalette() {
        openPalette()

        // The palette is 640 pt wide and centred; the left edge of the pane is outside it.
        app.element("smalti.terminal").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    private func expect(_ element: XCUIElement, valueEndsWith suffix: String) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", suffix), object: element)
        wait(for: [matched], timeout: 5)
    }

    // MARK: - The selected row stays in view (F3 Task 0)

    /// Accessibility frames are rounded to half points; a row flush with the list edge can land half a point out.
    private static let subpixelTolerance = 0.5

    func testArrowDownKeepsSelectedRowInsideTheList() {
        openPalette()
        let rows = app.elements("smalti.paletteRow")
        let count = rows.count
        XCTAssertGreaterThan(count, 1)
        XCTAssertFalse(
            isInsideTheList(rows.element(boundBy: count - 1)), "the list does not overflow: nothing to prove")

        for _ in 1..<count {
            app.typeKey(.downArrow, modifierFlags: [])
            assertSelectedRowIsInsideTheList()
        }
    }

    func testArrowUpWrapsAndRevealsLastRow() {
        openPalette()

        app.typeKey(.upArrow, modifierFlags: [])

        assertSelectedRowIsInsideTheList()
    }

    func testArrowDownPastTheEndRevealsFirstRowAndItsGroup() {
        openPalette()
        let firstTitle = app.elements("smalti.paletteRow").firstMatch.label
        app.typeKey(.upArrow, modifierFlags: [])

        app.typeKey(.downArrow, modifierFlags: [])

        XCTAssertEqual(selectedRow.label, firstTitle)
        assertSelectedRowIsInsideTheList()
        XCTAssertTrue(isInsideTheList(app.elements("smalti.paletteGroup").firstMatch))
    }

    /// F5.6: the trackpad or the wheel reaches the last command without the keyboard (the list used to hold only the
    /// rows around the selection, so the wheel ran out early).
    func testWheelScrollReachesLastCommand() {
        openPalette()
        let list = app.element("smalti.palette.list")
        let last = app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == 'Acerca de Smalti'"))
            .firstMatch
        XCTAssertFalse(isInsideTheList(last), "the list shows everything: nothing to prove")

        for _ in 0..<8 { list.scroll(byDeltaX: 0, deltaY: -400) }

        XCTAssertTrue(last.waitForExistence(timeout: 2))
        XCTAssertTrue(isInsideTheList(last))
    }

    func testClickingARowRunsIt() {
        openPalette()
        app.typeText("col")

        app.elements("smalti.paletteRow").firstMatch.click()

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
        expect(app.element("smalti.statusBar"), valueEndsWith: "· columnas")
    }

    // MARK: - F5.6: only the Claude integration action that applies

    private static let install = "Instalar integración con Claude Code"
    private static let uninstall = "Desinstalar integración con Claude Code"

    /// A new launch with a fake `claude` set up by `configure`, replacing the one from `setUp`.
    private func relaunch(_ configure: (XCUIApplication) -> Void) {
        let previous = app.configFile.deletingLastPathComponent()
        app.terminate()
        try? FileManager.default.removeItem(at: previous)
        let fresh = XCUIApplication.isolatedSmalti()
        configure(fresh)
        launch(fresh)
    }

    private func row(_ title: String) -> XCUIElement {
        app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Types the start of the title (no spaces: XCUITest sends them as ⌃Space on this layout).
    private func openPaletteOnIntegration() {
        openPalette()
        app.typeText("integraci")
    }

    /// What the fake `claude` was asked, for a failure message.
    private var claudeCalls: String {
        let file = app.configFile.deletingLastPathComponent().appending(path: "claude-calls")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? "no calls"
    }

    func testPaletteOffersInstallWhenNotInstalled() {
        relaunch { $0.useFakeClaude(installed: false) }

        openPaletteOnIntegration()

        XCTAssertTrue(row(Self.install).waitForExistence(timeout: 10), claudeCalls)
        XCTAssertFalse(row(Self.uninstall).exists)
    }

    func testPaletteOffersUninstallAfterInstall() {
        relaunch { $0.useFakeClaude(installed: false) }
        openPaletteOnIntegration()
        XCTAssertTrue(row(Self.install).waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [])

        openPaletteOnIntegration()

        XCTAssertTrue(row(Self.uninstall).waitForExistence(timeout: 10))
        XCTAssertFalse(row(Self.install).exists)
    }

    func testPaletteOffersNeitherWithoutClaude() {
        openPaletteOnIntegration()

        XCTAssertFalse(row(Self.install).waitForExistence(timeout: 3))
        XCTAssertFalse(row(Self.uninstall).exists)
    }

    func testExternalUninstallUpdatesOpenPalette() throws {
        var state: URL?
        relaunch { state = $0.useFakeClaude(installed: true) }
        openPaletteOnIntegration()
        XCTAssertTrue(row(Self.uninstall).waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        try FileManager.default.removeItem(at: try XCTUnwrap(state))

        openPaletteOnIntegration()

        XCTAssertTrue(row(Self.install).waitForExistence(timeout: 10))
        XCTAssertFalse(row(Self.uninstall).exists)
    }

    private var selectedRow: XCUIElement {
        app.elements("smalti.paletteRow").matching(NSPredicate(format: "value == 'selected'")).firstMatch
    }

    /// Polls for up to a second: the clip view scrolls with a short system animation, and the accessibility snapshot
    /// can land halfway through it.
    private func isInsideTheList(_ element: XCUIElement) -> Bool {
        let tolerance = -Self.subpixelTolerance
        let deadline = Date().addingTimeInterval(Self.settleTimeout)
        repeat {
            if app.element("smalti.palette.list").frame.insetBy(dx: tolerance, dy: tolerance).contains(element.frame) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.settlePoll))
        } while Date() < deadline
        return false
    }

    private static let settleTimeout: TimeInterval = 1
    private static let settlePoll: TimeInterval = 0.05

    private func assertSelectedRowIsInsideTheList(file: StaticString = #filePath, line: UInt = #line) {
        let selected = selectedRow
        XCTAssertTrue(selected.waitForExistence(timeout: 2), "no selected row", file: file, line: line)
        XCTAssertTrue(
            isInsideTheList(selected),
            "\(selected.label) at \(selected.frame) is not inside the list \(app.element("smalti.palette.list").frame)",
            file: file, line: line)
    }
}
