import XCTest

/// F7.7 (C1): with the app in English no interface text is Spanish. A walk through ⌘K, every menu, the help, the
/// Observatory, Appearance, the prompt studio, feedback, the session search, «About», the resume screen, status
/// messages (invalid config, no room for a pane) and the approval card; each surface's snapshot must hold no Spanish.
final class LocalizationTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }
    private var offenders: [String] = []

    /// Texts a test may meet that are not interface: fixture data and names.
    private static let allowed: Set<String> = ["Smalti", "Smalti Dev"]

    /// The app's windows only: the menu bar holds the system's Apple menu, written in the Mac's language.
    private func collect(_ surface: String) {
        let snapshots = app.windows.allElementsBoundByIndex.map(\.debugDescription)
        record(surface, snapshots.flatMap(SpanishText.visibleTexts))
    }

    private func record(_ surface: String, _ texts: [String]) {
        let found = texts.filter { !Self.allowed.contains($0) && SpanishText.looksSpanish($0) }
        offenders += Set(found).sorted().map { "\(surface): \($0)" }
    }

    private func close() {
        app.typeKey(.escape, modifierFlags: [])
    }

    private func runFromPalette(_ query: String) {
        openPalette()
        app.typeText(query)
        app.typeKey(.return, modifierFlags: [])
    }

    func testEnglishInterfaceHasNoSpanish() {
        let english = XCUIApplication.isolatedSmalti(language: "en")
        english.writeConfig("[appearance]\nblur = 999\n")
        launch(english)
        collect("window and status bar")

        openPalette()
        collect("palette")
        for _ in 0..<12 {
            for _ in 0..<12 { app.typeKey(.downArrow, modifierFlags: []) }
            collect("palette")
        }
        close()

        // Smalti's own menus: the first bar item is the system's Apple menu.
        for item in app.menuBars.menuBarItems.allElementsBoundByIndex.dropFirst() {
            item.click()
            record("menu \(item.title)", SpanishText.visibleTexts(in: item.debugDescription))
            close()
        }

        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))
        for _ in 0..<10 {
            collect("help")
            for _ in 0..<15 { app.typeKey(.downArrow, modifierFlags: []) }
        }
        close()

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.appearance").waitForExistence(timeout: 5))
        collect("appearance")
        close()

        runFromPalette("prompt studio")
        XCTAssertTrue(app.element("smalti.studio").waitForExistence(timeout: 5))
        collect("prompt studio")
        close()

        runFromPalette("report a problem")
        XCTAssertTrue(app.element("smalti.feedback").waitForExistence(timeout: 5))
        collect("feedback")
        close()

        app.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("sessions.search").waitForExistence(timeout: 5))
        collect("session search")
        close()

        runFromPalette("Welcome to Smalti")
        XCTAssertTrue(app.element("smalti.welcome").waitForExistence(timeout: 5))
        collect("welcome")
        close()

        runFromPalette("About Smalti")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        collect("about")

        XCTAssertTrue(offenders.isEmpty, "Spanish in the English interface: " + offenders.joined(separator: " | "))
    }

    func testEnglishObservatoryHasNoSpanish() throws {
        let english = XCUIApplication.isolatedSmalti(language: "en")
        try english.installObservatoryFixture(
            from: Bundle(for: Self.self), newestFirst: ["projects/-fixture-work-x/tools-session.jsonl"])
        launch(english)

        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'smalti.observatory.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        collect("observatory")
        app.typeKey("a", modifierFlags: [.command, .shift])
        collect("status bar figures")

        XCTAssertTrue(offenders.isEmpty, "Spanish in the English Observatory: " + offenders.joined(separator: " | "))
    }

    func testEnglishResumeScreenHasNoSpanish() {
        let english = XCUIApplication.isolatedSmalti(language: "en")
        SessionState.seed(
            [
                .init(
                    name: "web", root: "/tmp", layout: "columns",
                    panes: [
                        .init(directory: "/tmp", process: "zsh", lines: 120, commands: 4),
                        .init(directory: "/tmp", relaunch: ["nvim", "+3"], process: "nvim"),
                    ])
            ], alwaysRestore: false, in: english)
        self.app = english
        english.launch()

        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))
        collect("resume screen")

        XCTAssertTrue(offenders.isEmpty, "Spanish in the English resume screen: " + offenders.joined(separator: " | "))
    }

    func testEnglishStatusMessagesHaveNoSpanish() {
        launch(XCUIApplication.isolatedSmalti(config: "[appearance]\nblur = 99\n", language: "en"))
        let status = app.element("smalti.statusBar")
        let invalid = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (status.value as? String ?? "").contains("blur") }, object: nil)
        wait(for: [invalid], timeout: 10)
        record("invalid config", [status.value as? String ?? ""])

        // Splits until the window has no room for another pane (each ⌘D halves a pane).
        for _ in 0..<24 where !(status.value as? String ?? "").contains("No room") {
            app.typeKey("d", modifierFlags: .command)
        }
        XCTAssertTrue((status.value as? String ?? "").contains("No room"), status.value as? String ?? "")
        record("no room for a pane", [status.value as? String ?? ""])

        XCTAssertTrue(offenders.isEmpty, "Spanish in English status messages: " + offenders.joined(separator: " | "))
    }

    func testEnglishApprovalCardAndGuardReason() throws {
        launch(XCUIApplication.isolatedSmalti(language: "en"))
        let payload: [String: Any] = [
            "session_id": "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a", "hook_event_name": "PreToolUse", "cwd": "/tmp",
            "tool_name": "Bash", "tool_input": ["command": "terraform destroy -auto-approve"],
        ]
        let input = outputFile.appendingPathExtension("guard.json")
        let out = outputFile.appendingPathExtension("guard.out")
        try JSONSerialization.data(withJSONObject: payload).write(to: input)
        app.run(
            #"( "$SMALTI_CLI" guard PreToolUse < "\#(input.path(percentEncoded: false))" > "\#(out.path(percentEncoded: false))" ) &!"#
        )
        XCTAssertTrue(app.element("smalti.approvalCard").waitForExistence(timeout: 10))
        collect("approval card")
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        let rejected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? String(contentsOf: out, encoding: .utf8))?.contains("The user rejected this command") == true
            }, object: nil)
        wait(for: [rejected], timeout: 10)

        XCTAssertTrue(offenders.isEmpty, "Spanish in the English approval: " + offenders.joined(separator: " | "))
    }
}
