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
