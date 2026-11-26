import AppKit
import XCTest

/// F9: the timeline beside the panes (⇧⌘T) over the sanitized fixtures: the focused pane's session and following the
/// focus (C2), expanding and copying whole (C3), searching the project and jumping to a turn (C4), the empty state
/// and the fallback for a harness without a transcript.
final class TimelineTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }
    private typealias F = TimelineFixture
    private var longPrompt = ""

    /// Two panes in the fixture's folder: Claude's work-b session (hooks) and Codex's (binding); `third` adds one,
    /// given that folder.
    private func launchWithSessions(_ third: ((String) -> SessionState.Pane)? = nil) throws {
        let app = XCUIApplication.isolatedSmalti()
        let root = try F.root(for: app)
        longPrompt = try F.install(in: app, root: root, from: Bundle(for: Self.self))
        var panes: [SessionState.Pane] = [
            .init(directory: root, agentSessionID: F.workB, title: "fixture prompt B"),
            .init(directory: root, process: "codex", harness: ("codex", F.codex)),
        ]
        if let third { panes.append(third(root)) }
        SessionState.seed(
            [.init(name: "acme", root: root, layout: "columns", panes: panes)], alwaysRestore: true, in: app)
        launch(app, shells: panes.count)
    }

    private func openTimeline() {
        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.timeline").waitForExistence(timeout: 5))
    }

    private var title: XCUIElement { app.element("smalti.timeline.session.title") }

    private func expectTitle(_ text: String, prefixOnly: Bool = false, timeout: TimeInterval = 10) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { [title] _, _ in
                let shown = title.exists ? (title.value as? String ?? title.label) : ""
                return prefixOnly ? shown.hasPrefix(text) : shown == text
            }, object: nil)
        wait(for: [matched], timeout: timeout)
    }

    private func pasteboard(equals text: String, timeout: TimeInterval = 5) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in NSPasteboard.general.string(forType: .string) == text }, object: nil)
        wait(for: [matched], timeout: timeout)
    }

    private var chosenItem: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'smalti.timeline.item.' AND selected == true")
        ).firstMatch
    }

    private func terminal(_ index: Int) -> XCUIElement { app.elements("smalti.terminal").element(boundBy: index) }

    private func expect(_ terminal: XCUIElement, toContain text: String) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (terminal.value as? String)?.contains(text) == true }, object: nil)
        wait(for: [shown], timeout: 10)
    }

    private func press(_ key: XCUIKeyboardKey, times: Int = 1) {
        for _ in 0..<times { app.typeKey(key, modifierFlags: []) }
    }

    // MARK: - C2

    func testShowsTheFocusedPanesSessionAndFollowsTheFocus() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)

        openTimeline()
        expectTitle("fixture prompt B")
        app.typeKey("2", modifierFlags: .command)
        expectTitle("Run the shell command: ls")
        app.typeKey("1", modifierFlags: .command)
        expectTitle("fixture prompt B")
    }

    func testAPaneWithoutAgentShowsTheEmptyStateAndTheProjectsSessions() throws {
        try launchWithSessions { root in .init(directory: root) }
        app.typeKey("3", modifierFlags: .command)

        openTimeline()

        let empty = app.element("smalti.timeline.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.value as? String ?? empty.label, "Este panel no tiene un agente")
        XCTAssertTrue(app.element("smalti.timeline.recent.0").waitForExistence(timeout: 10))
    }

    // MARK: - C3

    func testExpandsAToolAndCopiesItsOutputAndCallWhole() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()
        expectTitle("fixture prompt B")

        press(.upArrow, times: 7)
        XCTAssertTrue(app.element("smalti.timeline.item.1").isSelected)
        press(.rightArrow)
        XCTAssertTrue(app.element("smalti.timeline.output").waitForExistence(timeout: 5))
        app.typeKey("c", modifierFlags: .command)
        pasteboard(equals: "Exit code 127\n(eval):1: command not found: eza")
        XCTAssertTrue((app.element("smalti.timeline.notice").value as? String ?? "").hasPrefix("Copiado"))
        app.typeKey("c", modifierFlags: [.command, .shift])
        pasteboard(equals: #"{"command":"ls","description":"List files in current directory"}"#)
        press(.leftArrow)
        XCTAssertFalse(app.element("smalti.timeline.output").exists)
    }

    func testCopiesALongPromptWhole() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()
        app.typeKey("f", modifierFlags: .command)
        app.typeText("resumen")
        XCTAssertTrue(app.element("smalti.timeline.hit.1").waitForExistence(timeout: 10))
        press(.downArrow)
        press(.return)
        expectTitle("Escribe un resumen largo.", prefixOnly: true)

        app.typeKey("c", modifierFlags: .command)

        pasteboard(equals: longPrompt)
        XCTAssertGreaterThan(longPrompt.count, 2_000)
    }

    // MARK: - C4

    func testSearchFindsAClosedSessionAndJumpsToTheTurn() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()
        expectTitle("fixture prompt B")

        app.typeKey("f", modifierFlags: .command)
        app.typeText("adios")
        XCTAssertTrue(app.element("smalti.timeline.hit.1").waitForExistence(timeout: 10))
        press(.downArrow)
        press(.return)

        expectTitle("fixture prompt F")
        let selected = chosenItem
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("adiós"), selected.label)
        XCTAssertTrue(selected.isHittable, "the chosen turn is in view")
    }

    // MARK: - Fallbacks and closing

    func testAHarnessWithoutTranscriptSaysSo() throws {
        try launchWithSessions { _ in .init(directory: "/tmp", process: "agy", harness: ("antigravity", "g1")) }
        app.typeKey("3", modifierFlags: .command)

        openTimeline()

        let empty = app.element("smalti.timeline.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.value as? String ?? empty.label, "Antigravity no deja un transcript que Smalti sepa leer")
    }

    func testEscClosesAndGivesTheKeyboardBack() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()

        press(.escape)
        XCTAssertTrue(app.element("smalti.timeline").waitForNonExistence(timeout: 5))
        app.run("echo vuelta-al-panel")

        expect(terminal(0), toContain: "vuelta-al-panel\n")
    }

    // MARK: - Review 2

    /// C1: with the timeline closed, ⇧⌘C and ⌘F are the terminal's.
    func testItsChordsBelongToTheTerminalWhileClosed() throws {
        try launchWithSessions()

        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.element("smalti.timeline").waitForExistence(timeout: 2))
        app.typeKey("f", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.search").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("smalti.timeline").exists)
    }

    /// C3: a click on a pane gives it the keyboard; ⌘2 then moves it to the other pane, as without the timeline.
    func testAClickOnAPaneGivesItTheKeyboardAndTheFocusMovesIt() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()

        terminal(0).click()
        app.run("echo en-el-uno")
        expect(terminal(0), toContain: "en-el-uno\n")
        app.typeKey("2", modifierFlags: .command)
        expectTitle("Run the shell command: ls")
        app.run("echo en-el-dos")

        expect(terminal(1), toContain: "en-el-dos\n")
    }

    /// I1: ⌘K over the timeline and esc: the timeline has the keyboard again.
    func testThePaletteGivesTheKeyboardBackToTheTimeline() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()
        expectTitle("fixture prompt B")
        let last = chosenItem.identifier

        openPalette()
        press(.escape)
        press(.upArrow)

        XCTAssertNotEqual(chosenItem.identifier, last)
    }

    func testTheProcessesViewAndTheTimelineNeverStack() throws {
        try launchWithSessions()
        openTimeline()

        app.typeKey("m", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.element("smalti.processes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("smalti.timeline").waitForNonExistence(timeout: 5))
    }

    /// I4: a hit in the session already shown only moves the choice.
    func testAHitInTheShownSessionOnlyMovesTheChoice() throws {
        try launchWithSessions()
        app.typeKey("1", modifierFlags: .command)
        openTimeline()
        expectTitle("fixture prompt B")

        app.typeKey("f", modifierFlags: .command)
        app.typeText("vacio")
        XCTAssertTrue(app.element("smalti.timeline.hit.1").waitForExistence(timeout: 10))
        press(.downArrow)
        press(.return)

        expectTitle("fixture prompt B")
        XCTAssertTrue(chosenItem.waitForExistence(timeout: 5))
        XCTAssertTrue(chosenItem.label.contains("vacío"), chosenItem.label)
    }

    func testTheObservatoryAndTheTimelineNeverStack() throws {
        try launchWithSessions()
        openTimeline()

        app.typeKey("a", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("smalti.timeline").waitForNonExistence(timeout: 5))
    }
}
