import XCTest

/// F6 (C4, C5): a harness started in a pane gets its session captured from its store and comes back with its own
/// resume command; without a session it comes back as "la última del directorio". The `codex` here is `/bin/cat`
/// copied and re-signed by the pane's shell into the test's Codex home, so no real Codex runs.
final class HarnessCaptureTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    func testCodexPaneCapturesAndRestoresWithResume() {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.run(app.fakeCodex(session: "fxcapture1"))
        sleep(4)

        let relaunched = quitAndRelaunch(app)

        XCTAssertTrue(relaunched.element("smalti.restore").waitForExistence(timeout: 10))
        let code = relaunched.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'codex resume fxca'"))
        XCTAssertTrue(code.firstMatch.waitForExistence(timeout: 5), "the restore row resumes the captured session")
        XCTAssertTrue(relaunched.staticTexts["Codex"].exists)
    }

    func testPaneWithoutSessionRestoresWithContinue() {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.run(app.fakeCodex(session: nil))
        sleep(2)

        let relaunched = quitAndRelaunch(app)

        XCTAssertTrue(relaunched.element("smalti.restore").waitForExistence(timeout: 10))
        XCTAssertTrue(relaunched.staticTexts["codex resume --last"].waitForExistence(timeout: 5))
        let detail = relaunched.staticTexts.matching(NSPredicate(format: "value ENDSWITH '· la última del directorio'"))
        XCTAssertTrue(detail.firstMatch.exists, "the row says it continues the directory's last session")
    }

    /// ⌘Q, confirming the running program, then the same isolated launch again.
    private func quitAndRelaunch(_ app: XCUIApplication) -> XCUIApplication {
        app.typeKey("q", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 5) { sheet.buttons["Cerrar"].click() }
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let again = XCUIApplication.relaunched(from: app)
        self.app = again
        again.launch()
        return again
    }
}

extension XCUIApplication {
    /// The value of a launch argument (`-SmaltiCodexHome <path>`).
    func launchArgument(_ name: String) -> String {
        guard let index = launchArguments.firstIndex(of: name), launchArguments.indices.contains(index + 1) else {
            return ""
        }
        return launchArguments[index + 1]
    }

    /// A shell line that makes a fake `codex` in the test's Codex home and runs it in the pane's directory; with a
    /// session id it first records that session there, as Codex would when the first message is sent.
    func fakeCodex(session: String?) -> String {
        let home = launchArgument("-SmaltiCodexHome")
        let table =
            "create table if not exists threads (id text, cwd text, title text, created_at integer, "
            + "updated_at integer, archived integer, source text);"
        let row =
            session.map {
                "insert into threads values ('\($0)', '$PWD', 'captura', strftime('%s','now') + 1, "
                    + "strftime('%s','now') + 1, 0, 'cli');"
            } ?? ""
        return "T='\(home)'; mkdir -p \"$T/bin\" && cp /bin/cat \"$T/bin/codex\" && codesign -f -s - \"$T/bin/codex\" "
            + "2>/dev/null && sqlite3 \"$T/state_5.sqlite\" \"\(table)\(row)\" && clear && \"$T/bin/codex\""
    }
}
