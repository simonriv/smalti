import XCTest

/// F6 (C8, C9): Neovim panes with their own socket (`nvim --clean`, `-SmaltiEditorSocketDir`), "Editados por Claude"
/// from injected `PostToolUse` events, ⌘⇧L and ⌘-click on `ruta:línea`.
final class EditorTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var socketDirectory: URL { URL(filePath: app.launchArgument("-SmaltiEditorSocketDir")) }
    private var work: String { socketDirectory.path(percentEncoded: false) + "-work" }

    override func setUp() async throws {
        try await super.setUp()
        let smalti = XCUIApplication.isolatedSmalti()
        smalti.launchArguments += ["-SmaltiExposeCellSize", "YES"]
        launch(smalti)
        app.run(
            "mkdir -p '\(work)' && cd '\(work)' && printf 'import x\\n\\nfunc greet() {\\n}\\n' > reminder.service.ts && clear"
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: work)
        try? FileManager.default.removeItem(at: socketDirectory)
        try await super.tearDown()
    }

    private func injectEdit() {
        let payload =
            #"{"session_id":"7f3a9c2e-0000-4000-8000-000000000001","tool_name":"Edit","tool_input":{"file_path":"\#(work)/reminder.service.ts","old_string":"x","new_string":"func greet() {"}}"#
        app.run("printf '%s' '\(payload)' | \"$SMALTI_CLI\" event PostToolUse && clear")
    }

    private func expectTerminals(_ count: Int) {
        let terminals = app.elements("smalti.terminal")
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == \(count)"), object: terminals)
        XCTAssertEqual(XCTWaiter().wait(for: [counted], timeout: 10), .completed, "expected \(count) panes")
    }

    private func expectSocketCount(_ count: Int) {
        let made = XCTNSPredicateExpectation(
            predicate: NSPredicate { [socketDirectory] _, _ in
                let names = (try? FileManager.default.contentsOfDirectory(atPath: socketDirectory.path)) ?? []
                return names.filter { $0.hasSuffix(".sock") }.count == count
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [made], timeout: 10), .completed, "expected \(count) Neovim sockets")
    }

    func testOpenBesideStartsNvimWithSocket() {
        app.typeKey("e", modifierFlags: [.command, .shift])

        expectTerminals(2)
        expectSocketCount(1)
    }

    func testEditedFilesGroupListsInjectedEdits() {
        injectEdit()
        sleep(1)

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.palette").waitForExistence(timeout: 5))
        app.typeText("reminder")

        let row = app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == 'reminder.service.ts'"))
        XCTAssertTrue(row.firstMatch.waitForExistence(timeout: 5))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'línea 3 · ahora'"))
        XCTAssertTrue(subtitle.firstMatch.exists, "the row says the line of the change")
    }

    func testLastEditedJumpsExistingNvim() {
        injectEdit()
        app.typeKey("e", modifierFlags: [.command, .shift])
        expectTerminals(2)
        expectSocketCount(1)
        sleep(1)
        app.typeKey("1", modifierFlags: .command)

        app.typeKey("l", modifierFlags: [.command, .shift])

        expectTerminals(2)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'focused'"),
            object: app.elements("smalti.pane").element(boundBy: 1))
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "the jump focuses the Neovim pane")
        let nvim = app.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("func greet()") == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "Neovim shows the edited file")
    }

    /// ⌘⇧E leaves the focus on Neovim; ⌘⇧L from there still finds the agent's edit.
    func testLastEditedFromTheNvimPane() {
        injectEdit()
        app.typeKey("e", modifierFlags: [.command, .shift])
        expectSocketCount(1)
        sleep(1)

        app.typeKey("l", modifierFlags: [.command, .shift])

        let nvim = app.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("func greet()") == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "Neovim shows the edited file")
    }

    func testCmdClickOnPathLineOpensNvim() {
        // Absolute: the tests' `zsh -f` does not report its directory, so a relative path has nothing to resolve against.
        app.run("echo '\(work)/reminder.service.ts:3'")
        sleep(1)

        app.element("smalti.terminal").commandClick(onRowStartingWith: "\(work)/reminder.service.ts:3")

        expectTerminals(2)
        expectSocketCount(1)
    }

    func testCmdClickOnBinaryDoesNotOpenNvim() {
        app.run("printf 'x\\000y' > blob.bin && clear && echo blob.bin")
        sleep(1)

        app.element("smalti.terminal").commandClick(onRowStartingWith: "blob.bin")

        sleep(2)
        XCTAssertEqual(app.elements("smalti.terminal").count, 1)
    }
}
