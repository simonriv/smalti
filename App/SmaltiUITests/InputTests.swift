import XCTest

/// F4 end to end (spec C2, C10, C11): ghost text, the Tab menu and the ⌃R palette in the real app with a real zsh,
/// and every key reaching programs that are not the prompt untouched.
final class InputTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    override func setUp() async throws {
        try await super.setUp()
        launch(.isolatedSmaltiWithIntegration())
        sleep(2)  // zsh's first prompt installs the input script.
    }

    private var terminalText: String { app.element("smalti.terminal").value as? String ?? "" }

    /// Pastes text without running it (spaces cannot be typed, see `run`).
    private func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    private func clearOutput() {
        try? FileManager.default.removeItem(at: outputFile)
    }

    private func waitForTerminal(containing text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if terminalText.contains(text) { return true }
            usleep(200_000)
        }
        return false
    }

    // MARK: Ghost text, Tab and ⌃R

    func testGhostTextIsAcceptedWithTheRightArrow() {
        app.typeText("<<<one>\"$SMALTI_UITEST_OUT\"\n")
        waitForOutput("one\n")
        clearOutput()

        app.typeText("<<<o")
        sleep(1)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeText("\n")

        waitForOutput("one\n")
    }

    func testTabOpensTheMenuForGit() {
        paste("git ch")

        app.typeKey(.tab, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.elements("smalti.completionRow").firstMatch.exists)
    }

    func testMenuEnterInsertsWithoutRunning() {
        paste("git ch")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.completionMenu").waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForTerminal(containing: "git checkout"))
        sleep(1)
        XCTAssertFalse(terminalText.contains("fatal:"), "the line ran instead of waiting")
    }

    func testCtrlROpensTheHistoryPalette() {
        app.typeText("<<<hist>\"$SMALTI_UITEST_OUT\"\n")
        waitForOutput("hist\n")

        app.typeKey("r", modifierFlags: .control)

        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        XCTAssertTrue(app.elements("smalti.historyRow").firstMatch.waitForExistence(timeout: 5))
    }

    func testHistoryScopeToggles() {
        app.typeKey("r", modifierFlags: .control)
        let directory = app.element("smalti.historyScopeDirectory")
        let everywhere = app.element("smalti.historyScopeAll")
        XCTAssertTrue(directory.waitForExistence(timeout: 5))
        XCTAssertTrue(directory.isSelected)
        XCTAssertFalse(everywhere.isSelected)

        app.typeKey(.tab, modifierFlags: [])

        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in everywhere.isSelected && !directory.isSelected }, object: nil)
        wait(for: [switched], timeout: 5)
    }

    func testHistoryCommandReturnRunsTheChosenLine() {
        app.typeText("<<<again>\"$SMALTI_UITEST_OUT\"\n")
        waitForOutput("again\n")
        clearOutput()

        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        app.typeText("again")
        XCTAssertTrue(app.elements("smalti.historyRow").firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.historyPalette").waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.terminal").count, 1, "⌘↩ must not reach Smalti's own shortcuts")
        waitForOutput("again\n")
    }

    func testHistoryEscapeLeavesTheLineUntouched() {
        app.typeText("abc")
        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.historyPalette").waitForNonExistence(timeout: 5))
        app.typeText("def")
        XCTAssertTrue(waitForTerminal(containing: "abcdef"))
    }

    // MARK: C2 — programs that are not the prompt get every key untouched

    func testKeysReachAProgramReadingTheTerminalUnchanged() {
        app.run("stty raw -echo; head -c 12 | od -An -tx1 | tr -d ' \\n' > \"$SMALTI_UITEST_OUT\"; stty sane")
        sleep(1)

        app.typeKey(.tab, modifierFlags: [])
        app.typeKey("r", modifierFlags: .control)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        waitForOutput("09121b5b431b5b411b5b421b")
        XCTAssertFalse(app.element("smalti.completionMenu").exists)
        XCTAssertFalse(app.element("smalti.historyPalette").exists)
    }

    func testLessReceivesItsSearch() {
        app.run("less /etc/hosts")
        sleep(1)

        app.typeText("/zzqqxx\n")

        XCTAssertTrue(waitForTerminal(containing: "Pattern not found"))
        app.typeText("q")
    }

    func testNvimReceivesTab() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/nvim"), "nvim not installed")
        app.run("/opt/homebrew/bin/nvim -u NONE -i NONE -n \"$SMALTI_UITEST_OUT\"")
        sleep(1)

        app.typeText("i")
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.typeText(":wq\n")

        waitForOutput("\t\n")
    }

    func testHtopQuitsWithQ() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/htop"), "htop not installed")
        app.run("/opt/homebrew/bin/htop")
        sleep(2)

        app.typeText("q")
        sleep(1)
        app.typeText("<<<back>\"$SMALTI_UITEST_OUT\"\n")

        waitForOutput("back\n")
    }

    // MARK: Block 4 review

    /// C1: another pane redrawing (here, its title changing all the time) never takes the keyboard from ⌃R.
    func testPaletteKeepsTheKeyboardWhileAnotherPaneRedraws() {
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(app.elements("smalti.terminal").element(boundBy: 1).waitForExistence(timeout: 10))
        sleep(2)
        app.run("while :; do print -n '\\e]0;t'$RANDOM'\\a'; sleep 0.1; done")
        app.typeKey("1", modifierFlags: .command)
        sleep(1)

        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        sleep(1)
        app.typeText("abc")
        sleep(1)

        XCTAssertEqual(app.element("smalti.historyField").value as? String, "abc")
    }

    /// I1: with the Tab menu open, ⌃R opens the palette, and its keys choose from the palette, not the menu.
    func testCtrlRWithTheMenuOpenUsesThePalette() {
        app.typeText("<<<hist>\"$SMALTI_UITEST_OUT\"\n")
        waitForOutput("hist\n")
        paste("git ch")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))

        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("smalti.completionMenu").waitForNonExistence(timeout: 5))
        app.typeText("hist")
        XCTAssertTrue(app.elements("smalti.historyRow").firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.historyPalette").waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForTerminal(containing: "p% <<<hist>\"$SMALTI_UITEST_OUT\"\np% <<<hist>"))
        XCTAssertFalse(terminalText.contains("git checkout"))
    }

    /// I2: a click outside closes the palette, and Smalti's shortcuts work again.
    func testClickingOutsideClosesThePalette() {
        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))

        app.element("smalti.terminal").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).click()

        XCTAssertTrue(app.element("smalti.historyPalette").waitForNonExistence(timeout: 5))
        openPalette()
    }
}
