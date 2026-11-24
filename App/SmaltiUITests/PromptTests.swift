import AppKit
import XCTest

/// F5 C7 and C12: the Smalti prompt in a real zsh (`zsh -d`, temporary ZDOTDIR whose `.zshrc` sets its own
/// `PS1`, which the Smalti prompt replaces), agents that start waiting, "Solo símbolo" and live changes.
final class PromptTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private func launchWithPrompt(theme: String? = nil) {
        let smalti = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
        if let theme { smalti.writeTheme(theme) }
        launch(smalti)
        sleep(2)  // zsh's first prompt installs the input and prompt scripts.
    }

    private func text(ofTerminal index: Int = 0) -> String {
        app.elements("smalti.terminal").element(boundBy: index).value as? String ?? ""
    }

    private func expectTerminal(_ index: Int = 0, containing fragment: String, timeout: TimeInterval = 10) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in text(ofTerminal: index).contains(fragment) }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [shown], timeout: timeout), .completed,
            "terminal \(index) has no \(fragment):\n\(text(ofTerminal: index))")
    }

    /// A repository on branch `feat` with one modified file, entered by the focused shell.
    private func enterRepository() {
        app.run(
            "cd \"$(mktemp -d)\" && git init -q -b feat && echo a >f && git add f && "
                + "git -c user.email=t@t -c user.name=t commit -qm i && echo b >f && clear")
    }

    func testDefaultPromptShowsDirectoryAndSymbol() {
        launchWithPrompt()

        app.run("cd /tmp")

        expectTerminal(containing: "/tmp")
        expectTerminal(containing: "›")
        XCTAssertFalse(text().contains("p% "), "the .zshrc PS1 won:\n\(text())")
    }

    func testGitRepoShowsBranchAndChanges() {
        launchWithPrompt()

        enterRepository()

        expectTerminal(containing: "feat")
        expectTerminal(containing: "●1")
    }

    func testSymbolOnlyMovesContextToHeader() {
        launchWithPrompt(theme: "[prompt]\nstyle = \"symbol-only\"\n")

        enterRepository()

        let header = app.element("smalti.paneHeader")
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (header.value as? String ?? "").contains("feat") }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 10), .completed, "header \(header.value ?? "")")
        XCTAssertFalse(text().contains("feat"), "the line kept the context:\n\(text())")
    }

    /// C12: the prompt changes in the shells already open, without running anything in them (`promptstyle`).
    func testThemeChangeRecolorsPromptLive() {
        launchWithPrompt()
        expectTerminal(containing: "›")

        app.writeTheme("[appearance]\ntheme = \"niebla\"\n\n[prompt]\nsymbol = \"λ\"\n")
        reloadConfigFromPalette()

        expectTerminal(containing: "λ")
    }

    // MARK: - F4 with the Smalti prompt (block 5 review, I5)

    func testGhostTextWorksUnderTheSmaltiPrompt() {
        launchWithPrompt()
        app.typeText("<<<one>\"$SMALTI_UITEST_OUT\"\n")
        waitForOutput("one\n")
        try? FileManager.default.removeItem(at: outputFile)

        app.typeText("<<<o")
        sleep(1)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeText("\n")

        waitForOutput("one\n")
    }

    func testTabMenuWorksUnderTheSmaltiPrompt() {
        launchWithPrompt()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("git ch", forType: .string)
        app.typeKey("v", modifierFlags: .command)

        app.typeKey(.tab, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))
    }
}
