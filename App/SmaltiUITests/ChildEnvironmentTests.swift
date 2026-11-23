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
}
