import XCTest

/// F4.5 C9, C10, C14, C15: font size (⌘+ ⌘− ⌘0, 6–72, new panes inherit), Igualar paneles on ⌃⌘=, select all,
/// copy and paste, ⌘L, prompt jumps, keys without modifiers unchanged, VoiceOver, and secure entry in the status bar.
final class TerminalBasicsTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var terminal: XCUIElement { app.element("smalti.terminal") }
    private var terminalText: String { terminal.value as? String ?? "" }

    private func launchExposingCellSize() {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiExposeCellSize", "YES"]
        launch(app)
    }

    /// The focused terminal's cell height in points, from `-SmaltiExposeCellSize` ("celda 8 × 21").
    private func cellHeight(_ element: XCUIElement? = nil) -> Double {
        let title = (element ?? terminal).title
        return Double(title.split(separator: " ").last ?? "") ?? 0
    }

    private func waitForCellHeight(_ condition: @escaping (Double) -> Bool, _ description: String) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in condition(cellHeight()) }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "\(description): \(cellHeight())")
    }

    func testFontKeysChangeTheSizeAndANewPaneInheritsIt() {
        launchExposingCellSize()
        let base = cellHeight()
        XCTAssertGreaterThan(base, 0)

        app.typeKey("+", modifierFlags: .command)
        waitForCellHeight({ $0 > base }, "⌘+ makes cells taller")
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)
        let newPane = app.elements("smalti.terminal").element(boundBy: 1)
        XCTAssertGreaterThan(cellHeight(newPane), base)

        app.typeKey("0", modifierFlags: .command)
        waitForCellHeight({ $0 == base }, "⌘0 goes back to the TOML's size")
        app.typeKey("-", modifierFlags: .command)
        waitForCellHeight({ $0 < base }, "⌘− makes cells shorter")
    }

    func testFontStopsAt72() {
        launchExposingCellSize()
        for _ in 0..<80 { app.typeKey("+", modifierFlags: .command) }
        let atMax = cellHeight()

        app.typeKey("+", modifierFlags: .command)

        XCTAssertEqual(cellHeight(), atMax)
    }

    func testControlCommandEqualsEqualizesThePanes() {
        launch(.isolatedSmalti())
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)
        app.typeKey(.rightArrow, modifierFlags: [.control, .command, .option])
        let resized = app.elements("smalti.terminal").element(boundBy: 0).frame.width

        app.typeKey("=", modifierFlags: [.control, .command])

        let equal = XCTNSPredicateExpectation(
            predicate: NSPredicate { [app] _, _ in
                // Safe: setUp launched `app` before this test and tearDown releases it after.
                let panes = app!.elements("smalti.terminal").allElementsBoundByIndex
                return panes.count == 2 && abs(panes[0].frame.width - panes[1].frame.width) < 2
                    && panes[0].frame.width != resized
            }, object: nil)
        wait(for: [equal], timeout: 5)
    }

    func testSelectAllCopyAndPasteRoundTrip() {
        launch(.isolatedSmalti())
        app.run("clear; echo copia-esta-linea")
        let printed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("copia-esta-linea\n") }, object: nil)
        // 10 s: under a full regression run the shell can take longer than 5 s to print (one flaky run seen).
        wait(for: [printed], timeout: 10)

        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)

        let copied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                NSPasteboard.general.string(forType: .string)?.contains("copia-esta-linea") == true
            }, object: nil)
        wait(for: [copied], timeout: 5)
    }

    func testCommandLClearsTheScreen() {
        launch(.isolatedSmalti())
        app.run("echo antes-de-limpiar")
        let printed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("antes-de-limpiar\n") }, object: nil)
        wait(for: [printed], timeout: 5)

        app.typeKey("l", modifierFlags: .command)

        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in !terminalText.contains("antes-de-limpiar") }, object: nil)
        wait(for: [cleared], timeout: 5)
    }

    /// OSC 133 marks the prompts: needs the shell integration (`zsh -d`, empty ZDOTDIR).
    func testCommandUpJumpsToThePreviousPrompt() {
        launch(.isolatedSmaltiWithIntegration())
        app.run("echo primero")
        app.run("for i in $(seq 1 200); do echo linea-$i; done")
        let scrolled = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("linea-200") }, object: nil)
        wait(for: [scrolled], timeout: 10)

        app.typeKey(.upArrow, modifierFlags: .command)

        let jumped = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                terminalText.contains("echo primero") || terminalText.contains("seq 1 200")
            },
            object: nil)
        wait(for: [jumped], timeout: 5)
        XCTAssertFalse(terminalText.contains("linea-200"))
    }

    func testVoiceOverReadsTheTerminalLabelAndOutput() {
        launch(.isolatedSmalti())

        app.run("echo hola-voiceover")

        XCTAssertEqual(terminal.label, "Terminal, panel 1, zsh")
        let read = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("hola-voiceover\n") }, object: nil)
        wait(for: [read], timeout: 5)
    }

    func testPasswordPromptShowsSecureEntryInTheStatusBar() {
        launch(.isolatedSmalti())
        let status = app.element("smalti.secureInput")

        app.run("read -s secreto")

        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Entrada segura'"), object: status)
        wait(for: [shown], timeout: 5)
        app.typeText("x\n")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == ''"), object: status)
        wait(for: [hidden], timeout: 5)
    }
}
