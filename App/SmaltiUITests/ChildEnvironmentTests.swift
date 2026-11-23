import XCTest

/// R1 / B13: every pane gets `SMALTI=1`, so a `.zshrc` can skip attaching to a shared tmux session, and opening
/// panes never adds clients to the user's tmux server.
final class ChildEnvironmentTests: SmaltiUITestCase {
    func testEachPaneSeesSmaltiVariable() {
        let clientsBefore = TmuxClients.count()
        app.typeText("<<<$SMALTI>>\"$SMALTI_UITEST_OUT\"\n")
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)

        app.typeText("<<<$SMALTI>>\"$SMALTI_UITEST_OUT\"\n")

        waitForOutput("1\n1\n")
        // Nil when the runner cannot reach a tmux server; the check is then done from the shell (see progress.md).
        if let clientsBefore { XCTAssertEqual(TmuxClients.count(), clientsBefore) }
    }

    /// Fail-closed guard: even if a login shell ever started in a test, `$TMUX` is set, so a `.zshrc` that attaches
    /// only when `$TMUX` is empty (Simón's does) never joins his `tmux main`.
    func testIsolatedShellsSeeTheTmuxGuard() {
        app.typeText("<<<${TMUX:+guarded}>>\"$SMALTI_UITEST_OUT\"\n")

        waitForOutput("guarded\n")
    }

    /// F2: a pane knows its identity and this Smalti's socket, and `smalti` resolves to the CLI in the bundle.
    func testPaneSeesSmaltiVariables() throws {
        app.run(
            #"print -r -- "$SMALTI_PANE_ID|${SMALTI_SOCKET:t}|${$(command -v smalti):h:t}/${$(command -v smalti):t}" > "$SMALTI_UITEST_OUT""#
        )

        let file = outputFile!
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (try? String(contentsOf: file, encoding: .utf8))?.isEmpty == false },
            object: nil)
        wait(for: [written], timeout: 10)
        let fields = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines)
            .split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 3)
        XCTAssertNotNil(UUID(uuidString: fields[0]))
        XCTAssertEqual(fields[1], "smalti.sock")
        XCTAssertEqual(fields[2], "bin/smalti")
    }
}
