import XCTest

/// ⌘K palette (B7, Paleta.dc.html). Typing avoids spaces: XCUITest sends them as ⌃Space on this layout.
@MainActor
final class CommandPaletteTests: XCTestCase {
    private var app: XCUIApplication!  // Set in setUp, before every test.

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.isolatedSmalti()
        app.launch()
        XCTAssertTrue(element("smalti.terminal").waitForExistence(timeout: 10))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testPaletteFiltersLayoutsAndSwitches() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("smalti.palette").waitForExistence(timeout: 5))

        app.typeText("col")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertFalse(element("smalti.palette").exists)
        expect(element("smalti.statusBar"), valueEndsWith: "· columnas")
    }

    func testEscapeClosesPalette() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("smalti.palette").waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    func testCommandKTogglesThePalette() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("smalti.palette").waitForExistence(timeout: 5))

        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(element("smalti.palette").waitForNonExistence(timeout: 5))
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

        XCTAssertTrue(element("smalti.palette").waitForNonExistence(timeout: 5))
        XCTAssertEqual(element("smalti.workspace").label, "solen")
    }

    func testEscapeCancelsRename() {
        let original = element("smalti.workspace").label
        openPalette()
        app.typeText("renombrar")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("zzz")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(element("smalti.palette").waitForNonExistence(timeout: 5))
        XCTAssertEqual(element("smalti.workspace").label, original)
    }

    func testClickOutsideClosesThePalette() {
        openPalette()

        // The palette is 640 pt wide and centred; the left edge of the pane is outside it.
        element("smalti.terminal").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        XCTAssertTrue(element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    private func openPalette() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("smalti.palette").waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func expect(_ element: XCUIElement, valueEndsWith suffix: String) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value ENDSWITH %@", suffix), object: element)
        wait(for: [matched], timeout: 5)
    }
}
