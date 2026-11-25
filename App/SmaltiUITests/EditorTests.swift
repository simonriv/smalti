import XCTest

/// F6 (C8, C9): Neovim panes with their own socket (`nvim --clean`, `-SmaltiEditorSocketDir`), "Editados por Claude"
/// from injected `PostToolUse` events, ⌘⇧L and ⌘-click on `ruta:línea`.
final class EditorTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var socketDirectory: URL { URL(filePath: app.launchArgument("-SmaltiEditorSocketDir")) }
    private var work: String { socketDirectory.path(percentEncoded: false) + "-work" }

    override func setUp() async throws {
        try await super.setUp()
        launch(.isolatedSmalti())
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

        XCTAssertTrue(app.staticTexts["reminder.service.ts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["línea 3 · ahora"].exists)
    }

    func testLastEditedJumpsExistingNvim() {
        injectEdit()
        app.typeKey("e", modifierFlags: [.command, .shift])
        expectTerminals(2)
        expectSocketCount(1)
        sleep(1)

        app.typeKey("l", modifierFlags: [.command, .shift])

        expectTerminals(2)
        let nvim = app.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("func greet()") == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "Neovim shows the edited file")
    }

    func testCmdClickOnPathLineOpensNvim() {
        app.run("echo reminder.service.ts:3")
        sleep(1)

        commandClickFirstWord()

        expectTerminals(2)
        expectSocketCount(1)
    }

    func testCmdClickOnBinaryDoesNotOpenNvim() {
        app.run("printf 'x\\000y' > blob.bin && clear && echo blob.bin")
        sleep(1)

        commandClickFirstWord()

        sleep(2)
        XCTAssertEqual(app.elements("smalti.terminal").count, 1)
    }

    /// ⌘-click on the first word of the line under the cleared screen's prompt.
    private func commandClickFirstWord() {
        let terminal = app.element("smalti.terminal")
        let line = terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 30))
        XCUIElement.perform(withKeyModifiers: .command) { line.click() }
    }
}
