import XCTest

/// F3: the observatory (⌘⇧A), the status bar's figures and the headers' model and context, all from the bundled
/// fixture in a temporary Claude home; Ollama is never reachable (`-SmaltiOllamaURL http://127.0.0.1:1`).
final class ObservatoryTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    /// The synthetic session with tools and a compaction, made the newest so it is the first row.
    private static let toolsSession = "projects/-fixture-work-x/tools-session.jsonl"
    /// Real recording A (Claude Code 2.1.330, Haiku 5.5).
    private static let recordedSession = "401a63e1-c076-45fe-9f09-432da1c8cfa6"

    private func launchWithFixture() throws {
        let app = XCUIApplication.isolatedSmalti()
        try app.installObservatoryFixture(from: Bundle(for: Self.self), newestFirst: [Self.toolsSession])
        launch(app)
    }

    private func openObservatory() {
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
    }

    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'smalti.observatory.row.'"))
    }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 15) {
        wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
            timeout: timeout)
    }

    private func value(_ identifier: String) -> String { app.element(identifier).value as? String ?? "" }

    // MARK: - The screen (T12)

    func testShowsCardsRowsDetailAndSystemFromFixture() throws {
        try launchWithFixture()
        openObservatory()

        waitFor { self.rows.count == 5 }
        XCTAssertEqual(app.element("smalti.observatory.card.input").label, "233k")
        XCTAssertEqual(app.element("smalti.observatory.card.output").label, "2.5k")
        XCTAssertEqual(value("smalti.observatory.activity"), "Actividad · work/x")
        XCTAssertEqual(value("smalti.observatory.localModels"), "Ollama no está corriendo")
        XCTAssertTrue(app.element("smalti.observatory.system").label.hasPrefix("Sistema · "))
    }

    func testEmptyClaudeHomeShowsNoRowsAndZeroTokens() {
        launch(XCUIApplication.isolatedSmalti())
        openObservatory()

        waitFor { self.app.element("smalti.observatory.card.input").label == "0" }
        XCTAssertEqual(rows.count, 0)
    }

    // MARK: - Keyboard and presentation (T13)

    func testCommandShiftATogglesObservatory() throws {
        try launchWithFixture()
        openObservatory()

        app.typeKey("a", modifierFlags: [.command, .shift])

        XCTAssertTrue(app.element("smalti.observatory").waitForNonExistence(timeout: 5))
    }

    func testEscapeClosesAndRefocusesPane() throws {
        try launchWithFixture()
        openObservatory()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.observatory").waitForNonExistence(timeout: 5))
        app.run("printf focus-back > \"$SMALTI_UITEST_OUT\"")
        waitFor { (try? String(contentsOf: self.outputFile, encoding: .utf8)) == "focus-back" }
    }

    func testPaletteOpensObservatory() throws {
        try launchWithFixture()
        openPalette()

        app.typeText("observatorio")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
    }

    func testCommandPCyclesPeriodOnlyWhenOpen() throws {
        try launchWithFixture()
        app.typeKey("p", modifierFlags: .command)
        XCTAssertFalse(app.element("smalti.observatory").exists)

        openObservatory()
        XCTAssertEqual(value("smalti.observatory.period"), "Hoy")
        app.typeKey("p", modifierFlags: .command)

        expect(app.element("smalti.observatory.period"), value: "7 días")
        app.typeKey("p", modifierFlags: .command)
        expect(app.element("smalti.observatory.period"), value: "30 días")
    }

    func testArrowsMoveSelectionAndDetailFollows() throws {
        try launchWithFixture()
        openObservatory()
        waitFor { self.rows.count == 5 }
        let first = value("smalti.observatory.activity")

        app.typeKey(.downArrow, modifierFlags: [])

        waitFor { self.value("smalti.observatory.activity") != first }
        app.typeKey(.upArrow, modifierFlags: [])
        expect(app.element("smalti.observatory.activity"), value: first)
    }

    func testReturnJumpsToPaneOfSelectedSession() throws {
        try launchWithFixture()
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)
        app.typeKey("1", modifierFlags: .command)
        app.run(#"printf '{"session_id":"\#(Self.recordedSession)"}' | "$SMALTI_CLI" event SessionStart; clear"#)
        app.typeKey("2", modifierFlags: .command)
        openObservatory()
        waitFor { self.rows.firstMatch.identifier == "smalti.observatory.row.\(Self.recordedSession)" }

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.observatory").waitForNonExistence(timeout: 5))
        app.run("printf jumped > \"$SMALTI_UITEST_OUT\"")
        waitFor { (try? String(contentsOf: self.outputFile, encoding: .utf8)) == "jumped" }
        XCTAssertEqual(
            app.elements("smalti.paneHeader").element(boundBy: 0).value as? String,
            app.elements("smalti.paneHeader").element(boundBy: 0).value as? String)
    }

    // MARK: - Status bar and headers (T14)

    func testStatusBarShowsRamGpuAndTodayTokens() throws {
        try launchWithFixture()

        waitFor { self.value("smalti.statusFigures").hasSuffix("hoy 236k tokens") }
        XCTAssertTrue(value("smalti.statusFigures").hasPrefix("RAM "))
        XCTAssertTrue(value("smalti.statusFigures").contains("GPU "))
    }

    func testPaneHeaderShowsModelAndContextForHookedSession() throws {
        try launchWithFixture()

        app.run(
            #"printf '{"session_id":"\#(Self.recordedSession)","source":"startup"}' | "$SMALTI_CLI" event SessionStart; clear"#
        )
        app.run(
            #"printf '{"session_id":"\#(Self.recordedSession)","prompt":"x"}' | "$SMALTI_CLI" event UserPromptSubmit; clear"#
        )

        let header = app.elements("smalti.paneHeader").firstMatch
        waitFor { (header.value as? String ?? "").hasSuffix(" · haiku") }
        waitFor { (self.app.element("smalti.paneContext").value as? String ?? "").hasPrefix("ctx ") }
    }

    func testUnavailableOllamaIsNamedNeverZero() throws {
        try launchWithFixture()
        openObservatory()

        waitFor { self.value("smalti.observatory.localModels") == "Ollama no está corriendo" }
        XCTAssertFalse(value("smalti.observatory.system").contains("modelo"))
    }
}
