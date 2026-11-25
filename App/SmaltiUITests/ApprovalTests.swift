import XCTest

/// F7.5 (C1, C8): guarded commands sent through the bundled `smalti guard` from a pane, as Claude Code's hook would,
/// wait on Smalti's card until the user decides. Never a real Claude: the hook payloads are written here.
final class ApprovalTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var notices: URL { outputFile.appendingPathExtension("notices") }
    private let session = "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"

    private static let replit = #"DATABASE_URL=postgres://u:p4ss@ep-x.neon.tech/db npm run db:push"#
    private static let dataTalks = "terraform destroy -auto-approve"
    private static let pocketOS = #"""
        curl -X POST https://backboard.railway.app/graphql/v2 -H "Authorization: Bearer $RAILWAY_TOKEN" -H "Content-Type: application/json" -d '{"query":"mutation { volumeDelete(volumeId: \"vol_1\") }"}'
        """#

    private func launchSmalti(_ extra: [String] = []) {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiNotificationLog", notices.path(percentEncoded: false)] + extra
        launch(app)
    }

    /// Writes the hook's JSON next to the output file and runs the CLI on it in the background (disowned, so closing
    /// the pane does not kill it); its stdout and exit status land in `out`.
    @discardableResult
    private func guardCommand(_ tool: [String: Any], name: String = "a") throws -> URL {
        let payload: [String: Any] = [
            "session_id": session, "hook_event_name": "PreToolUse", "cwd": "/tmp",
            "tool_name": tool["tool_name"] ?? "Bash",
            "tool_input": tool["tool_input"] ?? [:],
        ]
        let input = outputFile.appendingPathExtension("\(name).json")
        let out = outputFile.appendingPathExtension("\(name).out")
        try JSONSerialization.data(withJSONObject: payload).write(to: input)
        let (inPath, outPath) = (input.path(percentEncoded: false), out.path(percentEncoded: false))
        app.run(
            #"( "$SMALTI_CLI" guard PreToolUse < "\#(inPath)" > "\#(outPath)"; echo "exit=$?" >> "\#(outPath)" ) &!"#)
        return out
    }

    private func bash(_ command: String) -> [String: Any] {
        ["tool_name": "Bash", "tool_input": ["command": command]]
    }

    private func contents(_ file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    private func waitFor(_ file: URL, toContain text: String, timeout: TimeInterval = 10) {
        let done = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in contents(file).contains(text) }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [done], timeout: timeout), .completed, "\(file.lastPathComponent): \(contents(file))")
    }

    private var card: XCUIElement { app.element("smalti.approvalCard") }

    private func expectCard(command: String, environment: String) {
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let shown = app.element("smalti.approvalCommand")
        XCTAssertTrue((shown.value as? String ?? "").contains(command), "card shows \(shown.value ?? "nil")")
        let subject = app.element("smalti.approvalEnvironment")
        let named = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (subject.value as? String ?? "").contains("contra \(environment)") },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [named], timeout: 5), .completed, "subject: \(subject.value ?? "nil")")
    }

    /// The hook has not answered: nothing written, not even its exit status.
    private func expectStillWaiting(_ out: URL) {
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(contents(out), "", "the hook answered before the user decided")
    }

    // MARK: - C1: the three incidents

    func testReplitDbPushWaitsAndApprovesSilently() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.replit))

        expectCard(command: "npm run db:push", environment: "PROD")
        expectStillWaiting(out)
        app.typeKey(.return, modifierFlags: [.command, .shift])

        waitFor(out, toContain: "exit=0")
        XCTAssertEqual(contents(out), "exit=0\n")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    func testDataTalksTerraformDestroyRejectedFromPalette() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.dataTalks))

        expectCard(command: "terraform destroy", environment: "PROD")
        expectStillWaiting(out)
        openPalette()
        app.typeText("rechazar")
        app.typeKey(.return, modifierFlags: [])

        waitFor(out, toContain: "exit=0")
        XCTAssertTrue(contents(out).contains(#""permissionDecision":"deny""#))
        XCTAssertTrue(contents(out).contains("rechazó en Smalti"))
    }

    func testPocketOSRailwayCurlRejectedByKeyboard() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.pocketOS))

        expectCard(command: "backboard.railway.app", environment: "PROD")
        expectStillWaiting(out)
        app.typeKey(.escape, modifierFlags: [.command, .shift])

        waitFor(out, toContain: "exit=0")
        XCTAssertTrue(contents(out).contains(#""permissionDecision":"deny""#))
    }

    // MARK: - C8: the card, the pane and the notification

    func testQueueShowsOneOfTwo() throws {
        launchSmalti()
        let first = try guardCommand(bash(Self.dataTalks), name: "a")
        expectCard(command: "terraform destroy", environment: "PROD")
        let second = try guardCommand(bash("supabase db push"), name: "b")

        expect(card, value: "1 de 2")
        app.typeKey(.return, modifierFlags: [.command, .shift])
        waitFor(first, toContain: "exit=0")
        expect(card, value: "1 de 1")
        XCTAssertEqual(contents(second), "")
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        waitFor(second, toContain: "exit=0")
    }

    func testPaneIsAmberAndNotifies() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.dataTalks))
        expectCard(command: "terraform destroy", environment: "PROD")

        expect(app.elements("smalti.paneStatus").firstMatch, value: "waiting")
        let noticed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                contents(notices).contains("Aprobación: `terraform destroy` contra PROD")
            }, object: nil)
        wait(for: [noticed], timeout: 5)

        app.typeKey(.return, modifierFlags: [.command, .shift])
        waitFor(out, toContain: "exit=0")
        expect(app.elements("smalti.paneStatus").firstMatch, value: "working")
    }

    func testExpiryDenies() throws {
        launchSmalti(["-SmaltiApprovalTimeoutSeconds", "3"])
        let out = try guardCommand(bash(Self.dataTalks))

        waitFor(out, toContain: "exit=0", timeout: 15)
        XCTAssertTrue(contents(out).contains("Nadie aprobó el comando en Smalti"))
    }

    func testClosingPaneDenies() throws {
        launchSmalti()
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)
        let out = try guardCommand(bash(Self.dataTalks))
        expectCard(command: "terraform destroy", environment: "PROD")

        app.typeKey("w", modifierFlags: .command)

        waitFor(out, toContain: "exit=0")
        XCTAssertTrue(contents(out).contains("se cerró antes de aprobar"))
    }

    func testSecretDeniedWithoutCard() throws {
        launchSmalti()
        let out = try guardCommand(["tool_name": "Read", "tool_input": ["file_path": "/tmp/x/.env"]])

        waitFor(out, toContain: "exit=0")
        XCTAssertTrue(contents(out).contains(#""permissionDecision":"deny""#))
        XCTAssertFalse(card.exists)
        let status = app.element("smalti.statusBar")
        let said = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (status.value as? String ?? "").contains("bloqueó la lectura de /tmp/x/.env")
            },
            object: nil)
        wait(for: [said], timeout: 5)
    }

    // MARK: - Intermediate review 2

    /// M6: the keys decide even while the help or the search bar is open.
    func testKeysDecideWithHelpOpen() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.dataTalks))
        expectCard(command: "terraform destroy", environment: "PROD")
        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: [.command, .shift])

        waitFor(out, toContain: "exit=0")
        XCTAssertEqual(contents(out), "exit=0\n")
    }

    /// M3: a theme change restyles a card already shown.
    func testCardFollowsTheTheme() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.dataTalks))
        expectCard(command: "terraform destroy", environment: "PROD")
        let before = card.title

        openPalette()
        app.typeText("siguientetema")
        app.typeKey(.return, modifierFlags: [])

        let restyled = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in card.title != before && !card.title.isEmpty }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [restyled], timeout: 5), .completed, "card theme: \(card.title)")
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        waitFor(out, toContain: "exit=0")
    }

    /// M5: in a small pane the card stays inside it.
    func testCardFitsASmallPane() throws {
        launchSmalti()
        // Splits until no other pane fits ("No cabe otro panel"): the focused pane is the smallest one.
        for _ in 2...9 {
            let before = app.elements("smalti.pane").count
            app.typeKey("d", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.6)
            if app.elements("smalti.pane").count == before { break }
        }
        waitForShells(count: app.elements("smalti.pane").count)
        let out = try guardCommand(bash(Self.pocketOS + "\n" + String(repeating: "# line\n", count: 20)))
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        let pane = app.elements("smalti.pane").matching(NSPredicate(format: "value == 'focused'")).firstMatch
        XCTAssertTrue(pane.frame.insetBy(dx: -1, dy: -1).contains(card.frame), "card \(card.frame) pane \(pane.frame)")
        XCTAssertGreaterThan(card.frame.width, 0)
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        waitFor(out, toContain: "exit=0")
    }

    // MARK: - Captures (on demand: TEST_RUNNER_SMALTI_CAPTURE=1)

    private func capture(_ element: XCUIElement, as name: String) throws {
        let captures = FileManager.default.temporaryDirectory.appending(path: "smalti-captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try element.screenshot().pngRepresentation.write(to: captures.appending(path: name))
    }

    func testCaptureCardAndPalette() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_CAPTURE"] == "1", "captures run on demand")
        launchSmalti()
        let first = try guardCommand(bash("supabase db push"), name: "a")
        expectCard(command: "supabase db push", environment: "PROD")
        let second = try guardCommand(bash(Self.pocketOS), name: "b")
        expect(card, value: "1 de 2")
        usleep(300_000)

        try capture(card, as: "f75-approval-card.png")
        try capture(app.windows.firstMatch, as: "f75-approval-window.png")
        openPalette()
        app.typeText("aprobar")
        usleep(300_000)
        try capture(app.element("smalti.palette"), as: "f75-palette-approvals.png")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(.escape, modifierFlags: [.command, .shift])
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        waitFor(first, toContain: "exit=0")
        waitFor(second, toContain: "exit=0")
    }

    func testCardIsRedacted() throws {
        launchSmalti()
        let out = try guardCommand(bash(Self.replit))
        expectCard(command: "npm run db:push", environment: "PROD")

        XCTAssertFalse((app.element("smalti.approvalCommand").value as? String ?? "").contains("p4ss"))
        app.typeKey(.escape, modifierFlags: [.command, .shift])
        waitFor(out, toContain: "exit=0")
    }
}
