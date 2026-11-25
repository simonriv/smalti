import XCTest

/// F6 (C5, C6): the restore screen shows each harness's own command, and its right column is the session search,
/// reached with Tab; esc there never discards the saved session, and ↩ restores what is checked, then opens.
final class RestoreSearchTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private func launchToRestore(_ panes: [SessionState.Pane]) {
        let app = XCUIApplication.isolatedSmalti()
        app.seedHarnessStoresFromRunner()
        SessionState.seed(
            [.init(name: "solen", root: "/tmp", layout: "dwindle", panes: panes)], alwaysRestore: false,
            in: app)
        self.app = app
        app.launchEnvironment["SMALTI_UITEST_OUT"] = outputFile.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))
    }

    func testRowsShowEachHarnessCommand() {
        launchToRestore([
            .init(directory: "/tmp", process: "codex", harness: ("codex", "0198abcdef")),
            .init(directory: "/tmp", process: "antigravity", harness: ("antigravity", "c41e5555")),
            .init(directory: "/tmp", process: "opencode", harness: ("opencode", "ses_abcdef")),
            .init(directory: "/usr", process: "antigravity", harness: ("antigravity", nil)),
        ])

        for code in ["codex resume 0198…", "agy --conversation c41e…", "opencode -s ses_…", "agy -c"] {
            XCTAssertTrue(app.staticTexts[code].waitForExistence(timeout: 5), "row with \(code)")
        }
        XCTAssertTrue(app.staticTexts["la última del directorio"].exists)
    }

    func testTabMovesFocusBetweenColumns() {
        launchToRestore([.init(directory: "/tmp")])
        XCTAssertTrue(app.element("sessions.row.fxcodex1").waitForExistence(timeout: 5))

        app.typeKey(.tab, modifierFlags: [])
        app.typeText("calendario")

        let field = app.element("sessions.field")
        XCTAssertEqual(field.value as? String, "calendario")
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "calendario", "the list has the keys again")
    }

    func testEscInSearchColumnReturnsFocusWithoutDiscarding() {
        launchToRestore([.init(directory: "/tmp")])
        app.typeKey(.tab, modifierFlags: [])

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.restore").exists, "esc in the search does not start clean")
        XCTAssertFalse(app.element("smalti.terminal").exists)
    }

    func testEnterOnSessionRestoresThenOpens() {
        launchToRestore([.init(directory: "/tmp"), .init(directory: "/usr")])
        XCTAssertTrue(app.element("sessions.row.fxcodex1").waitForExistence(timeout: 5))
        app.typeKey(.tab, modifierFlags: [])
        app.typeText("calendario")

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.restore").waitForNonExistence(timeout: 10))
        let terminals = app.elements("smalti.terminal")
        let three = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: terminals)
        wait(for: [three], timeout: 10)
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                terminals.allElementsBoundByIndex.contains {
                    ($0.value as? String)?.contains("codex resume fxcodex1") == true
                }
            }, object: nil)
        wait(for: [typed], timeout: 10)
    }
}

extension XCUIApplication {
    /// The stores of `seedHarnessStores()`, written by the test runner itself (before any pane exists) with the
    /// system's sqlite3.
    func seedHarnessStoresFromRunner() {
        let line = seedHarnessStores()
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", line]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            XCTFail("could not seed the harness stores: \(error)")
        }
        XCTAssertEqual(process.terminationStatus, 0, "seeding the harness stores")
    }
}
