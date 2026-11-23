import XCTest

/// Panes by keyboard (spec F1: B15, B16, Review Focus 2).
final class TilingTests: SmaltiUITestCase {
    func testNewPaneSplitsAndShowsThreePanes() {
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("d", modifierFlags: .command)

        waitForPaneCount(3)
        let summary = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "\(workspaceName) · 3 paneles · dwindle"),
            object: app.element("smalti.statusBar"))
        wait(for: [summary], timeout: 5)
    }

    /// Review Focus 2: after closing the focused pane, typing reaches the pane that took the focus.
    func testClosingFocusedPaneMovesKeyboardFocus() {
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("d", modifierFlags: .command)
        waitForPaneCount(3)

        app.typeKey("w", modifierFlags: .command)
        waitForPaneCount(2)
        app.run("<<<focused>\"$SMALTI_UITEST_OUT\"")

        waitForOutput("focused\n")
        XCTAssertEqual(pane("Panel 2").value as? String, "focused")
    }

    /// The first pane runs `cat`; `exit` in the second closes only the second.
    func testExitClosesOnlyThatPane() {
        app.typeText("cat\n")
        app.typeKey("d", modifierFlags: .command)
        waitForPaneCount(2)

        app.typeText("exit\n")

        waitForPaneCount(1)
        expect(app.element("smalti.paneHeader"), label: "cat")
        XCTAssertTrue(app.windows["smalti.window"].exists)
    }

    /// B15: closing the last pane leaves the workspace empty and the window open.
    func testLastPaneLeavesWindowOpen() {
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.emptyWorkspace").waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows["smalti.window"].exists)
    }

    /// B14: the header names the foreground process and goes back to the shell when it ends.
    func testHeaderShowsForegroundProcess() {
        let header = app.element("smalti.paneHeader")

        app.typeText("cat\n")
        expect(header, label: "cat")
        app.typeKey("d", modifierFlags: .control)

        expect(header, label: "zsh")
    }

    /// B16: ⌘K and ⌘1 reach Smalti, not the terminal's own bindings (cleared, R6).
    func testCmdKAndCmd1ReachSmaltiNotTheTerminal() {
        app.typeKey("d", modifierFlags: .command)
        waitForPaneCount(2)

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.palette").waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("1", modifierFlags: .command)

        XCTAssertEqual(pane("Panel 1").value as? String, "focused")
    }

    /// The app names the first workspace after its home folder; the test runner's own home may differ.
    private var workspaceName: String {
        app.element("smalti.workspace").label
    }

    private func pane(_ label: String) -> XCUIElement {
        app.elements("smalti.pane").matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func expect(_ element: XCUIElement, label: String) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        wait(for: [matched], timeout: 5)
    }
}
