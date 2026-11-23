import XCTest

/// F2 part B: reopening brings the saved workspaces back.
final class SessionRestoreTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    func testAlwaysRestoreReopensWorkspaces() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "/tmp", layout: "columns",
                    panes: [.init(directory: "/tmp"), .init(directory: "/usr")]),
                .init(name: "rizaria", root: "/usr", layout: "dwindle", panes: [.init(directory: "/usr")]),
            ], alwaysRestore: true, in: app)

        launch(app, shells: 2)

        let pills = app.elements("smalti.workspace")
        XCTAssertEqual(pills.allElementsBoundByIndex.map(\.label), ["solen", "rizaria"])
        expect(app.element("smalti.statusBar"), value: "solen · 2 paneles · columnas")
    }

    // MARK: - Quit and relaunch

    /// C7: what a shell printed comes back after ⌘Q, under the "restaurado" banner.
    func testQuitAndRelaunchRestoresScrollback() {
        let first = XCUIApplication.isolatedSmalti()
        launch(first)
        first.run(#"printf '\e[32m%s\e[0m\n' verde-smalti"#)
        expectTerminal(of: first, toContain: "verde-smalti")

        let relaunched = quitAndRelaunch(first)
        XCTAssertTrue(relaunched.element("smalti.restore").waitForExistence(timeout: 10))
        relaunched.typeKey(.return, modifierFlags: [])

        expectTerminal(of: relaunched, toContain: "verde-smalti")
        expectTerminal(of: relaunched, toContain: "restaurado ·")
    }

    // MARK: - Resume screen

    func testResumeScreenListsWorkspacesAndCounts() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "/tmp", layout: "dwindle",
                    panes: [.init(directory: "/tmp"), .init(directory: "/usr")]),
                .init(name: "rizaria", root: "/usr", layout: "columns", panes: [.init(directory: "/usr")]),
            ], alwaysRestore: false, in: app)

        launchToResumeScreen(app)

        XCTAssertTrue(app.staticTexts["Retomar donde quedaste"].exists)
        XCTAssertTrue(app.staticTexts["Dwindle · 2 paneles"].exists)
        XCTAssertTrue(app.staticTexts["Columnas · 1 panel"].exists)
        XCTAssertEqual(app.element("restore.primary").label, "Restaurar 3 paneles")
        XCTAssertEqual(app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH 'restore.row.'")).count, 3)
    }

    func testResumeScreenIsKeyboardOnly() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "/tmp", layout: "dwindle",
                    panes: [.init(directory: "/tmp"), .init(directory: "/usr"), .init(directory: "/var")])
            ],
            alwaysRestore: false, in: app)
        launchToResumeScreen(app)

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        XCTAssertEqual(app.element("restore.primary").label, "Restaurar 2 paneles")
        app.typeKey(.return, modifierFlags: [])

        waitForShells(count: 2)
        expect(app.element("smalti.statusBar"), value: "solen · 2 paneles · dwindle")
    }

    func testLayoutsOnlyOpensCleanShells() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "/tmp", layout: "dwindle",
                    panes: [.init(directory: "/tmp", agentSessionID: "7f3a9c2e")])
            ],
            alwaysRestore: false, in: app)
        launchToResumeScreen(app)

        app.typeKey("l", modifierFlags: .command)

        waitForShells(count: 1)
        let text = app.element("smalti.terminal").value as? String ?? ""
        XCTAssertFalse(text.contains("--resume"))
    }

    func testStartCleanKeepsSnapshotUntilNextSave() throws {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [.init(name: "rizaria", root: "/usr", layout: "dwindle", panes: [.init(directory: "/usr")])],
            alwaysRestore: false, in: app)
        let session = app.stateDirectory.appending(path: "session.json")
        launchToResumeScreen(app)

        app.typeKey(.escape, modifierFlags: [])
        waitForShells(count: 1)
        XCTAssertTrue(try String(contentsOf: session, encoding: .utf8).contains("rizaria"))

        app.typeKey("d", modifierFlags: .command)
        let replaced = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? String(contentsOf: session, encoding: .utf8)).map { !$0.contains("rizaria") } ?? false
            }, object: nil)
        wait(for: [replaced], timeout: 6)
    }

    func testAlwaysRestoreIsToggledWithCommandComma() throws {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [.init(name: "solen", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])],
            alwaysRestore: false, in: app)
        launchToResumeScreen(app)

        app.typeKey(",", modifierFlags: .command)

        let preferences = try String(
            contentsOf: app.stateDirectory.appending(path: "preferences.json"), encoding: .utf8)
        XCTAssertTrue(preferences.contains("always"))
    }

    // MARK: - Helpers

    private func launchToResumeScreen(_ app: XCUIApplication) {
        self.app = app
        app.launchEnvironment["SMALTI_UITEST_OUT"] = outputFile.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))
    }

    /// ⌘Q (so the app saves), then the same isolated launch again.
    private func quitAndRelaunch(_ app: XCUIApplication) -> XCUIApplication {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let again = XCUIApplication()
        again.launchArguments = app.launchArguments
        again.launchEnvironment = app.launchEnvironment
        self.app = again
        again.launch()
        return again
    }

    private func expectTerminal(of app: XCUIApplication, toContain text: String) {
        let terminal = app.element("smalti.terminal")
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (terminal.value as? String)?.contains(text) == true }, object: nil)
        wait(for: [shown], timeout: 10)
    }
}
