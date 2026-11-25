import XCTest

/// F6 (C6): the session search card (⌘⇧O) over stores seeded in the test's own harness homes.
final class SessionSearchTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var card: XCUIElement { app.element("sessions.search") }

    override func setUp() async throws {
        try await super.setUp()
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.run(app.seedHarnessStores() + " && clear")
        sleep(1)
    }

    private func openCard() {
        app.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private func rows() -> [String] {
        app.elements(matchingPrefix: "sessions.row.").allElementsBoundByIndex.map(\.label)
    }

    func testChipsHaveNoGemini() {
        openCard()

        let chips = (0..<6).compactMap { index -> String? in
            let chip = app.element("sessions.chip.\(index)")
            return chip.exists ? chip.label : nil
        }
        XCTAssertEqual(chips, ["Todas", "Claude Code", "Codex", "Antigravity", "OpenCode"])
    }

    func testChipFiltersHarness() {
        openCard()
        XCTAssertTrue(app.element("sessions.row.fxcodex1").waitForExistence(timeout: 5))

        app.element("sessions.chip.3").click()

        XCTAssertTrue(app.element("sessions.row.fxagy1").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("sessions.row.fxcodex1").exists)
    }

    func testTypingFilters() {
        openCard()
        XCTAssertTrue(app.element("sessions.row.fxcodex1").waitForExistence(timeout: 5))

        app.typeText("calendario")

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.element("sessions.row.fxagy1"))
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.element("sessions.row.fxcodex1").exists)
    }

    func testEnterOpensPaneWithResumeCommand() {
        openCard()
        XCTAssertTrue(app.element("sessions.row.fxcodex1").waitForExistence(timeout: 5))
        app.typeText("calendario")

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.terminal").count, 2)
        expectFocusedTerminal(toContain: "codex resume fxcodex1")
    }

    func testCmdEnterOnAntigravityShowsCannotFork() {
        openCard()
        app.element("sessions.chip.3").click()
        XCTAssertTrue(app.element("sessions.row.fxagy1").waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: .command)

        XCTAssertTrue(app.staticTexts["Antigravity no permite bifurcar sesiones"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.terminal").count, 1)
    }

    private func expectChosenChip(_ index: Int) {
        let chosen = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'selected'"), object: app.element("sessions.chip.\(index)"))
        XCTAssertEqual(XCTWaiter().wait(for: [chosen], timeout: 5), .completed, "chip \(index) chosen")
    }

    func testCmdDigitChoosesChip() {
        openCard()

        app.typeKey("3", modifierFlags: .command)

        expectChosenChip(2)
        XCTAssertEqual(app.elements("smalti.terminal").count, 1, "⌘3 did not reach the panes behind")
    }

    func testArrowsChangeChipWithEmptyField() {
        openCard()

        app.typeKey(.rightArrow, modifierFlags: [])

        expectChosenChip(1)
    }

    func testEscClosesTheCard() {
        openCard()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    func testReopenedCardStartsEmpty() {
        openCard()
        app.element("sessions.chip.2").click()
        expectChosenChip(2)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        openCard()

        XCTAssertEqual(app.element("sessions.field").value as? String ?? "", "")
        expectChosenChip(0)
        XCTAssertTrue(app.element("sessions.row.fxagy1").waitForExistence(timeout: 5), "every harness listed again")
    }

    func testMissingDirectoryOpensHomeWithNotice() {
        openCard()
        app.element("sessions.chip.4").click()
        XCTAssertTrue(app.element("sessions.row.fxoc1").waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["La carpeta de la sesión ya no existe: /tmp/smalti-fx-gone"].waitForExistence(timeout: 5))
        expectFocusedTerminal(toContain: "opencode -s fxoc1")
    }

    private func expectFocusedTerminal(toContain text: String) {
        let terminals = app.elements("smalti.terminal")
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                terminals.allElementsBoundByIndex.contains { ($0.value as? String)?.contains(text) == true }
            }, object: nil)
        wait(for: [shown], timeout: 10)
    }
}

extension XCUIApplication {
    func elements(matchingPrefix prefix: String) -> XCUIElementQuery {
        descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    /// One shell line that writes small Codex, Antigravity and OpenCode stores into the test's homes: a Codex
    /// session in `/tmp`, an Antigravity one in `/usr` and an OpenCode one whose folder does not exist.
    func seedHarnessStores() -> String {
        let codex = launchArgument("-SmaltiCodexHome")
        let antigravity = launchArgument("-SmaltiAntigravityHome")
        let opencode = launchArgument("-SmaltiOpenCodeDB")
        let now = "strftime('%s','now')"
        let codexSQL =
            "create table threads (id text, cwd text, title text, created_at integer, updated_at integer, "
            + "archived integer, source text); insert into threads values ('fxcodex1', '/tmp', "
            + "'Endpoint de calendario compartido', \(now) - 100, \(now) - 100, 0, 'cli');"
        let agySQL =
            "create table conversation_summaries (conversation_id text, title text, preview text, "
            + "workspace_uris text, last_modified_time text); insert into conversation_summaries values ('fxagy1', "
            + "'Componentes de la landing', '', '[\"file:///usr\"]', strftime('%Y-%m-%d %H:%M:%f+00:00','now'));"
        let ocSQL =
            "create table session_v2 (id text, parent_id text, directory text, title text, time_created integer, "
            + "time_updated integer, time_archived integer, tokens_input integer, tokens_output integer, "
            + "tokens_cache_read integer); create table session_message (id text, session_id text, type text, "
            + "seq integer, data text); insert into session_v2 values ('fxoc1', null, '/tmp/smalti-fx-gone', "
            + "'Spec del hito 3', \(now) * 1000 - 300000, \(now) * 1000 - 300000, null, 10, 5, 0); "
            + "insert into session_message values ('m1', 'fxoc1', 'assistant', 1, "
            + "'{\"model\":{\"id\":\"qwen3:4b\",\"providerID\":\"ollama\"}}');"
        return "mkdir -p '\(codex)' '\(antigravity)' \"$(dirname '\(opencode)')\" && "
            + "sqlite3 '\(codex)/state_5.sqlite' \"\(codexSQL)\" && "
            + "sqlite3 '\(antigravity)/conversation_summaries.db' \"\(agySQL.replacingOccurrences(of: "\"", with: "\\\""))\" && "
            + "sqlite3 '\(opencode)' \"\(ocSQL.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
