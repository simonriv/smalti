import XCTest

/// Workspaces by keyboard (spec F1: B9 automated, strip).
final class WorkspaceTests: SmaltiUITestCase {
    func testNewWorkspaceAddsAPillAndCtrl1GoesBack() {
        app.typeKey("n", modifierFlags: [.control, .command])
        let pills = app.elements("smalti.workspace")
        XCTAssertTrue(pills.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(pills.element(boundBy: 1).value as? String, "active")

        app.typeKey("1", modifierFlags: .control)

        XCTAssertEqual(pills.element(boundBy: 0).value as? String, "active")
    }

    /// B9, automated with a marker file instead of `say`: a process keeps running in a hidden workspace.
    func testWorkspaceSwitchKeepsProcessesAlive() {
        app.run("sleep 2; <<<listo>\"$SMALTI_UITEST_OUT\"")

        app.typeKey("n", modifierFlags: [.control, .command])
        XCTAssertTrue(app.elements("smalti.workspace").element(boundBy: 1).waitForExistence(timeout: 5))

        waitForOutput("listo\n", timeout: 10)
    }
}
