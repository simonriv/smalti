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
        XCTAssertEqual(app.element("smalti.timeline.item.1").value as? String, "selected")
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
        let selected = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'smalti.timeline.item.' AND value == 'selected'")
        ).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("adiós"), selected.label)
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
        openTimeline()

        press(.escape)

        XCTAssertTrue(app.element("smalti.timeline").waitForNonExistence(timeout: 5))
    }

    func testTheObservatoryAndTheTimelineNeverStack() throws {
        try launchWithSessions()
        openTimeline()

        app.typeKey("a", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("smalti.timeline").waitForNonExistence(timeout: 5))
    }
}
