import XCTest

/// F4.5 C3, C14: the help lists every shortcut and action; ⌘? opens it from the keyboard, ⌘K and the Help menu; typing
/// filters, ↩ runs the selected row, esc closes; it is labelled for VoiceOver.
final class HelpTests: SmaltiUITestCase {
    private var help: XCUIElement { app.element("smalti.help") }

    private func openWithCommandQuestionMark() {
        app.typeKey("?", modifierFlags: [.command, .shift])
        XCTAssertTrue(help.waitForExistence(timeout: 5))
    }

    func testCommandQuestionMarkOpensTheHelp() {
        openWithCommandQuestionMark()

        XCTAssertTrue(app.staticTexts["Nueva ventana"].exists)
        XCTAssertTrue(app.staticTexts["EN EL PROMPT"].exists)
    }

    func testHelpOpensFromThePaletteAndTheHelpMenu() {
        openPalette()
        app.typeText("ayuda de smalti")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(help.waitForNonExistence(timeout: 5))

        app.menuBars.menuBarItems["Ayuda"].click()
        app.menuBars.menuItems["Ayuda de Smalti"].click()

        XCTAssertTrue(help.waitForExistence(timeout: 5))
    }

    func testTypingFilters() {
        openWithCommandQuestionMark()

        app.typeText("ventana")

        let rows = app.elements("smalti.helpRow")
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                rows.count > 0 && rows.allElementsBoundByIndex.allSatisfy { $0.label.lowercased().contains("ventana") }
            }, object: nil)
        wait(for: [filtered], timeout: 5)
    }

    func testRowsWithoutKeysHaveNoDanglingComma() {
        openWithCommandQuestionMark()
        app.typeText("127.0.0.1")

        let rows = app.elements("smalti.helpRow")
        let privacy = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in rows.count > 0 }, object: nil)
        wait(for: [privacy], timeout: 5)
        let labels = rows.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.hasSuffix(", ") }, "\(labels)")
    }

    func testReturnRunsTheSelectedCommand() {
        openWithCommandQuestionMark()
        app.typeText("nuevo panel")

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(help.waitForNonExistence(timeout: 5))
        waitForShells(count: 2)
    }

    func testEscapeClosesAndTheTerminalGetsTheKeyboardBack() {
        openWithCommandQuestionMark()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(help.waitForNonExistence(timeout: 5))
        app.typeText("echo ayuda-cerrada\n")
        let terminal = app.element("smalti.terminal")
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (terminal.value as? String)?.contains("ayuda-cerrada") == true },
            object: nil)
        wait(for: [typed], timeout: 5)
    }

    func testHelpHasAccessibilityLabels() {
        openWithCommandQuestionMark()

        XCTAssertEqual(help.label, "Ayuda de Smalti")
        XCTAssertEqual(app.element("smalti.helpField").placeholderValue, "Buscar atajos y acciones")
        let row = app.elements("smalti.helpRow").firstMatch
        XCTAssertTrue(row.label.contains("⌘N") || row.label.contains("en ⌘K"), "row label: \(row.label)")
    }
}
