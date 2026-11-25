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

    /// A pane that cannot come back as saved (here, an agent of a harness Smalti does not know yet) is reported.
    func testPartlyRestoredLayoutIsReported() throws {
        let layouts = app.stateDirectory.appending(path: "layouts")
        try FileManager.default.createDirectory(at: layouts, withIntermediateDirectories: true)
        let layout = #"""
            {"name":"x","rootDirectory":"/tmp","layout":"dwindle","focusedIndex":0,"panes":[{"id":"\#(UUID().uuidString)",
            "workingDirectory":"/tmp","scrollbackLines":0,"commandCount":0,
            "agent":{"harness":"gemini","sessionID":"0198","lastState":"waiting"}}]}
            """#
        try Data(layout.utf8).write(to: layouts.appending(path: "con-gemini.json"))

        runFromPalette("con-gemini")

        let reported = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "No se restauró todo"),
            object: app.element("smalti.statusBar"))
        wait(for: [reported], timeout: 5)
    }

    func testFailedLayoutSaveIsReported() throws {
        let layouts = app.stateDirectory.appending(path: "layouts")
        try FileManager.default.createDirectory(
            at: layouts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o500])
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: layouts.path(percentEncoded: false))
        }

        runFromPalette("no-cabe")

        let reported = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "No se pudo guardar el layout"),
            object: app.element("smalti.statusBar"))
        wait(for: [reported], timeout: 5)
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
