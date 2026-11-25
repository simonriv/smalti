import XCTest

/// F6: a Smalti Neovim is saved at its file and line (`EditorBridge.current`, 200 ms) and reopens there with its socket;
/// one that does not answer is saved as its process. `nvim --clean` with the test's own socket folder.
final class EditorRestoreTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var socketDirectory: String { app.launchArgument("-SmaltiEditorSocketDir") }
    private var work: String { socketDirectory + "-work" }

    override func setUp() async throws {
        try await super.setUp()
        launch(.isolatedSmalti(config: "[window]\nconfirm_close = false\n"))
        let lines = "$(seq -f 'line-%g' 1 200)"
        app.run("mkdir -p '\(work)' && cd '\(work)' && printf '%s\\n' \(lines) > notes.txt && clear")
    }

    override func tearDown() async throws {
        // A stopped Neovim (the unresponsive case) never outlives the test.
        let kill = Process()
        kill.executableURL = URL(filePath: "/bin/sh")
        kill.arguments = ["-c", "pkill -CONT -f -- '\(socketDirectory)'; pkill -KILL -f -- '\(socketDirectory)'; true"]
        try? kill.run()
        kill.waitUntilExit()
        try? FileManager.default.removeItem(atPath: work)
        try? FileManager.default.removeItem(atPath: socketDirectory)
        try await super.tearDown()
    }

    /// ⌘-click on `notes.txt:150`: a Neovim with its socket at line 150.
    private func openNvimAtLine150() {
        app.run("echo notes.txt:150")
        sleep(1)
        let terminal = app.element("smalti.terminal")
        let line = terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 30))
        XCUIElement.perform(withKeyModifiers: .command) { line.click() }
        let nvim = app.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("line-150") == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "Neovim opened at line 150")
    }

    private func quit() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }

    /// The saved panes of the first workspace, as `FileSessionArchive` wrote them.
    private func savedPanes() throws -> [[String: Any]] {
        let data = try Data(contentsOf: app.stateDirectory.appending(path: "session.json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let windows = try XCTUnwrap(root["windows"] as? [[String: Any]])
        let workspaces = try XCTUnwrap(windows.first?["workspaces"] as? [[String: Any]])
        return try XCTUnwrap(workspaces.first?["panes"] as? [[String: Any]])
    }

    func testNvimPaneRestoresAtFileAndLine() throws {
        openNvimAtLine150()
        quit()

        let editor = try XCTUnwrap(try savedPanes().compactMap { $0["editor"] as? [String: Any] }.first)
        XCTAssertEqual(editor["line"] as? Int, 150)
        XCTAssertEqual((editor["file"] as? String)?.hasSuffix("/notes.txt"), true)

        let again = XCUIApplication()
        again.launchArguments = app.launchArguments
        again.launchEnvironment = app.launchEnvironment
        app = again
        again.launch()
        XCTAssertTrue(again.element("smalti.restore").waitForExistence(timeout: 10))
        again.typeKey(.return, modifierFlags: [])
        let nvim = again.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("line-150") == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "Neovim reopened at line 150")
    }

    func testUnresponsiveNvimRestoresAsProcess() throws {
        openNvimAtLine150()
        let stop = Process()
        stop.executableURL = URL(filePath: "/usr/bin/pkill")
        stop.arguments = ["-STOP", "-f", "--", socketDirectory]
        try stop.run()
        stop.waitUntilExit()

        quit()

        let nvimPane = try XCTUnwrap(
            try savedPanes().first { ($0["relaunch"] as? [String: Any]).map { "\($0)".contains("nvim") } ?? false },
            "the stopped Neovim is saved as its process")
        XCTAssertNil(nvimPane["editor"])
    }
}
