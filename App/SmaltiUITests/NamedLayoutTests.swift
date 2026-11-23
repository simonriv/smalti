import XCTest

/// C10: a layout saved by name opens again as a new workspace, with the program its pane was running.
final class NamedLayoutTests: SmaltiUITestCase {
    func testSaveAndRestoreNamedLayout() {
        app.run("sleep 300")
        expectHeader("sleep")

        runFromPalette("smalti-prueba")
        expect(app.element("smalti.statusBar"), value: "Layout “smalti-prueba” guardado")
        app.typeKey("c", modifierFlags: .control)
        expectHeader("zsh")

        runFromPalette("smalti-prueba")

        let pills = app.elements("smalti.workspace")
        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in pills.allElementsBoundByIndex.map(\.label).contains("smalti-prueba") },
            object: nil)
        wait(for: [opened], timeout: 5)
        expectHeader("sleep")
    }

    /// Types `query` in ⌘K and runs the first result.
    private func runFromPalette(_ query: String) {
        openPalette()
        app.typeText(query)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    private func expectHeader(_ process: String) {
        let header = app.elements("smalti.paneHeader").firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", process), object: header)
        wait(for: [shown], timeout: 10)
    }
}
