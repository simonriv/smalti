import XCTest

/// F6 (C12): the observatory's harness chips over an OpenCode store seeded in the test's own home.
final class ObservatoryFilterTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    override func setUp() async throws {
        try await super.setUp()
        let app = XCUIApplication.isolatedSmalti()
        app.seedHarnessStoresFromRunner()
        launch(app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory.filter.0").waitForExistence(timeout: 10))
    }

    private var opencodeRow: XCUIElement { app.staticTexts["OpenCode · qwen3:4b local"] }

    func testChipsFilterTable() {
        XCTAssertTrue(opencodeRow.waitForExistence(timeout: 10), "Todas shows OpenCode's session")

        app.element("smalti.observatory.filter.1").click()
        XCTAssertTrue(opencodeRow.waitForNonExistence(timeout: 5), "Claude Code hides it")

        app.element("smalti.observatory.filter.3").click()
        XCTAssertTrue(opencodeRow.waitForExistence(timeout: 5), "Locales shows the local model's session")
        XCTAssertTrue(
            app.staticTexts[
                "Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."
            ].exists)
    }

    func testCmdShiftFCyclesFilters() {
        app.typeKey("f", modifierFlags: [.command, .shift])

        let chosen = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'selected'"), object: app.element("smalti.observatory.filter.1"))
        XCTAssertEqual(XCTWaiter().wait(for: [chosen], timeout: 5), .completed)
    }
}
