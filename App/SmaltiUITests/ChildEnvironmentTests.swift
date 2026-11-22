import XCTest

/// R1 / B13: every pane gets `SMALTI=1`, so a `.zshrc` can skip attaching to a shared tmux session.
final class ChildEnvironmentTests: SmaltiUITestCase {
    func testEachPaneSeesSmaltiVariable() {
        app.typeText("<<<$SMALTI>>\"$SMALTI_UITEST_OUT\"\n")
        app.typeKey("d", modifierFlags: .command)
        waitForPaneCount(2)
        sleep(2)  // The new pane's zsh prints its prompt.

        app.typeText("<<<$SMALTI>>\"$SMALTI_UITEST_OUT\"\n")

        waitForOutput("1\n1\n")
    }
}
