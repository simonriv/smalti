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

    func testRenameWorkspaceFromPalette() {
        app.typeKey("k", modifierFlags: .command)
        app.typeText("renombrar")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)

        app.typeText("solen")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.descendants(matching: .any)["smalti.workspace"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["smalti.workspace"].firstMatch.label, "solen")
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
