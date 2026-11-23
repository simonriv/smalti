import XCTest

/// F4.5 C7: closing a pane, a workspace, a window or the app asks first while a program runs in it; at the shell
/// prompt nothing asks; `[window] confirm_close = false` never asks.
final class CloseConfirmationTests: SmaltiUITestCase {
    private var sheet: XCUIElement { app.sheets.firstMatch }

    /// `sleep 100` in the focused pane, until its header names it.
    private func startSleeping() {
        app.run("sleep 100")
        let header = app.element("smalti.paneHeader")
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'sleep'"), object: header)
        wait(for: [running], timeout: 10)
    }

    private func expectQuestion(_ title: String) {
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "no question for \(title)")
        XCTAssertTrue(sheet.staticTexts[title].exists, "the sheet does not ask \(title)")
    }

    func testClosingABusyPaneAsks() {
        startSleeping()

        app.typeKey("w", modifierFlags: .command)

        expectQuestion("¿Cerrar el panel?")
        XCTAssertTrue(sheet.staticTexts["sleep 100 sigue en marcha. Si cierras el panel, el proceso termina."].exists)
        sheet.buttons["Cerrar"].click()
        XCTAssertTrue(app.element("smalti.paneHeader").waitForNonExistence(timeout: 5))
    }

    func testCancelKeepsThePane() {
        startSleeping()
        app.typeKey("w", modifierFlags: .command)
        expectQuestion("¿Cerrar el panel?")

        sheet.buttons["Cancelar"].click()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.element("smalti.paneHeader").label, "sleep")
    }

    func testClosingAnIdlePaneDoesNotAsk() {
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.paneHeader").waitForNonExistence(timeout: 5))
        XCTAssertFalse(sheet.exists)
    }

    func testClosingAWorkspaceWithABusyPaneAsks() {
        startSleeping()
        app.typeKey("n", modifierFlags: [.control, .command])
        waitForShells(count: 1)
        app.typeKey("1", modifierFlags: .control)
        openPalette()
        app.typeText("cerrar workspace")
        app.typeKey(.return, modifierFlags: [])

        expectQuestion("¿Cerrar el workspace “\(app.elements("smalti.workspace").firstMatch.label)”?")
        XCTAssertTrue(sheet.staticTexts["Hay 1 proceso en marcha: sleep 100."].exists)
    }

    func testClosingAWindowWithABusyPaneAsks() {
        startSleeping()
        app.typeKey("n", modifierFlags: .command)
        // The first pane runs `sleep`, so only the new one is at a `zsh` prompt: count the headers instead.
        let headers = app.elements("smalti.paneHeader")
        let two = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in headers.count == 2 }, object: nil)
        wait(for: [two], timeout: 10)
        app.windows.matching(identifier: "smalti.window").element(boundBy: 1).click()

        app.typeKey("w", modifierFlags: [.shift, .command])

        expectQuestion("¿Cerrar la ventana?")
    }

    func testQuitAsksAndCancelKeepsRunning() {
        startSleeping()

        app.typeKey("q", modifierFlags: .command)

        expectQuestion("¿Salir de Smalti?")
        sheet.buttons["Cancelar"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Block 3 review: with the window minimized, ⌘Q brings it back and asks where the user can see it.
    func testQuitWithTheWindowMinimizedShowsTheQuestion() {
        startSleeping()
        let window = app.windows.matching(identifier: "smalti.window").firstMatch
        app.typeKey("m", modifierFlags: .command)
        let minimized = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: window)
        wait(for: [minimized], timeout: 10)

        app.typeKey("q", modifierFlags: .command)

        expectQuestion("¿Salir de Smalti?")
        sheet.buttons["Cancelar"].click()
    }

    /// Review Focus 3: what runs in a hidden workspace counts too.
    func testQuitCountsABusyPaneInAHiddenWorkspace() {
        startSleeping()
        app.typeKey("n", modifierFlags: [.control, .command])
        waitForShells(count: 1)

        app.typeKey("q", modifierFlags: .command)

        expectQuestion("¿Salir de Smalti?")
        XCTAssertTrue(
            sheet.staticTexts["Hay 1 proceso en marcha. Al volver podrás retomarlos desde Reanudar."].exists)
        sheet.buttons["Cancelar"].click()
    }

    func testConfirmCloseFalseNeverAsks() {
        app.terminate()
        let relaunched = XCUIApplication.isolatedSmalti(config: "[window]\nconfirm_close = false\n")
        launch(relaunched)
        startSleeping()

        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.paneHeader").waitForNonExistence(timeout: 5))
        XCTAssertFalse(sheet.exists)
    }
}
