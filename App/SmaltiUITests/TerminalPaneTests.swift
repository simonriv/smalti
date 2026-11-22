import XCTest

/// The pane hosts a live libghostty surface whose shell receives typed input.
final class TerminalPaneTests: XCTestCase {
    private var app: XCUIApplication!  // Assigned in setUp before every test; XCTest has no init-time setup.
    private var outputFile: URL!  // Same: created per test in setUp.

    override func setUpWithError() throws {
        continueAfterFailure = false
        outputFile = FileManager.default.temporaryDirectory.appending(path: "smalti-uitest-\(UUID().uuidString)")
        app = XCUIApplication.isolatedSmalti()
        app.launchEnvironment["SMALTI_UITEST_OUT"] = outputFile.path(percentEncoded: false)
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: outputFile)
    }

    func testPaneHostsTerminalSurface() {
        let terminal = app.descendants(matching: .any)["smalti.terminal"].firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(terminal.frame.width, 0)
        XCTAssertGreaterThan(terminal.frame.height, 0)
    }

    func testTypingReachesShell() throws {
        let terminal = app.descendants(matching: .any)["smalti.terminal"].firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 5))
        sleep(2)  // Let zsh print its first prompt before typing.

        // No spaces: on the Latin American layout XCUITest synthesizes " " as ⌃Space, which a terminal
        // correctly sends as NUL. zsh writes a here-string to the file with no command (NULLCMD=cat).
        // Real space input is checked by hand (F0 spec, A11).
        app.typeText("<<<smalti-ok>\"$SMALTI_UITEST_OUT\"\n")

        let written = expectation(
            for: NSPredicate { _, _ in
                (try? String(contentsOf: self.outputFile, encoding: .utf8)) == "smalti-ok\n"
            }, evaluatedWith: nil)
        wait(for: [written], timeout: 10)
    }
}
