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

    func testArrowDownKeepsSelectedRowInsideTheList() {
        openPalette()
        let count = app.elements("smalti.paletteRow").count

        for _ in 1..<max(count, 1) {
            app.typeKey(.downArrow, modifierFlags: [])
            assertSelectedRowIsInsideTheList()
        }
    }

    func testArrowUpWrapsAndRevealsLastRow() {
        openPalette()

        app.typeKey(.upArrow, modifierFlags: [])

        assertSelectedRowIsInsideTheList()
    }

    func testArrowDownPastTheEndRevealsFirstRow() {
        openPalette()
        app.typeKey(.upArrow, modifierFlags: [])

        app.typeKey(.downArrow, modifierFlags: [])

        assertSelectedRowIsInsideTheList()
        assertInsideTheList(app.staticTexts["TILING"])
    }

    private func assertSelectedRowIsInsideTheList(file: StaticString = #filePath, line: UInt = #line) {
        let selected = app.elements("smalti.paletteRow").matching(NSPredicate(format: "value == 'selected'")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 2), "no selected row", file: file, line: line)
        assertInsideTheList(selected, file: file, line: line)
    }

    private func assertInsideTheList(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let list = app.element("smalti.palette.list").frame
        XCTAssertTrue(
            list.insetBy(dx: -0.5, dy: -0.5).contains(element.frame),
            "\(element.label) at \(element.frame) is not inside the list \(list)", file: file, line: line)
    }
}
