import XCTest

/// F6: a Smalti Neovim is saved at its file and line (`EditorBridge.current`, 200 ms) and reopens there with its socket;
/// one that does not answer is saved as its process. `nvim --clean` with the test's own socket folder.
final class EditorRestoreTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var socketDirectory: String { app.launchArgument("-SmaltiEditorSocketDir") }
    private var work: String { socketDirectory + "-work" }

    override func setUp() async throws {
        try await super.setUp()
        let smalti = XCUIApplication.isolatedSmalti(config: "[window]\nconfirm_close = false\n")
        smalti.launchArguments += ["-SmaltiExposeCellSize", "YES"]
        launch(smalti)
        let lines = "$(seq -f 'line-%g' 1 200)"
        app.run("mkdir -p '\(work)' && cd '\(work)' && printf '%s\\n' \(lines) > notes.txt && clear")
    }

    override func tearDown() async throws {
        // Best effort: the runner may not signal the app's processes, so the busy Neovim also has its own killer.
        let kill = Process()
        kill.executableURL = URL(filePath: "/bin/sh")
        kill.arguments = ["-c", "pkill -KILL -f -- '\(socketDirectory)'; true"]
        try? kill.run()
        kill.waitUntilExit()
        try? FileManager.default.removeItem(atPath: work)
        try? FileManager.default.removeItem(atPath: socketDirectory)
        try await super.tearDown()
    }

    /// ⌘-click on `notes.txt:150`: a Neovim with its socket at line 150.
    private func openNvimAtLine150() {
        // Absolute: the tests' `zsh -f` does not report its directory.
        app.run("echo '\(work)/notes.txt:150'")
        sleep(1)
        app.element("smalti.terminal").commandClick(onRowStartingWith: "\(work)/notes.txt:150")
        let nvim = app.elements("smalti.terminal").element(boundBy: 1)
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (nvim.value as? String)?.contains("line-150") == true }, object: nil)
        let terminals = app.elements("smalti.terminal").allElementsBoundByIndex.map {
            ($0.value as? String ?? "").suffix(600)
        }
        XCTAssertEqual(
            XCTWaiter().wait(for: [shown], timeout: 10), .completed,
            "Neovim opened at line 150; terminals: \(terminals)")
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
        // A Neovim busy in Lua still owns the terminal (a SIGSTOP would hand it back to zsh) but answers no RPC. The
        // keys go from the first pane's shell, which reaches the socket as the app does.
        app.typeKey("1", modifierFlags: .command)
        app.run(
            "/opt/homebrew/bin/nvim --clean --headless --server '\(socketDirectory)'/*.sock "
                + "--remote-send ':lua while true do end<CR>'")
        sleep(2)
        // The test runner cannot signal the app's processes: the shell leaves a detached killer for the busy Neovim.
        app.run("(sleep 5; pkill -KILL -f -- '\(socketDirectory)/') &!")

        quit()

        let panes = try savedPanes()
        let nvimPane = try XCTUnwrap(
            panes.first { ($0["relaunch"] as? [String: Any]).map { "\($0)".contains("nvim") } ?? false },
            "the busy Neovim is saved as its process; saved: \(panes)")
        XCTAssertNil(nvimPane["editor"])
    }
}
