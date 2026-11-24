import AppKit
import XCTest

/// F5 C5 and C15: the native window buttons hidden, on hover or visible (`mockup-buttons`), and "Reducir movimiento".
final class WindowButtonsTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let buttonIdentifiers = [XCUIIdentifierCloseWindow, XCUIIdentifierMinimizeWindow]
    /// The strip's leading padding, plus 72 px when the buttons have their margin.
    private static let pillOffset: CGFloat = 16
    private static let shiftedPillOffset: CGFloat = 16 + 72

    private var window: XCUIElement { app.windows.matching(identifier: "smalti.window").firstMatch }
    private var close: XCUIElement { window.buttons[XCUIIdentifierCloseWindow] }
    /// The green button: accessibility keeps calling it the full-screen button although it zooms (`performZoom`).
    private var zoom: XCUIElement {
        window.buttons.matching(
            NSPredicate(format: "identifier IN %@", [XCUIIdentifierZoomWindow, XCUIIdentifierFullScreenWindow])
        ).firstMatch
    }

    private func launch(buttons mode: String, reduceMotion: Bool = false) {
        let smalti = XCUIApplication.isolatedSmalti(config: "[window]\nbuttons = \"\(mode)\"\n")
        if reduceMotion { smalti.launchArguments += ["-SmaltiReduceMotion", "YES"] }
        launch(smalti)
    }

    private var pillOffset: CGFloat {
        window.descendants(matching: .any)["smalti.workspace"].firstMatch.frame.minX - window.frame.minX
    }

    private func waitUntil(_ element: XCUIElement, exists: Bool, timeout: TimeInterval = 5) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == %@", NSNumber(value: exists)), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: timeout), .completed, "exists should be \(exists)")
    }

    func testHiddenShowsNoButtons() {
        launch(buttons: "hidden")

        for identifier in Self.buttonIdentifiers { XCTAssertFalse(window.buttons[identifier].exists, identifier) }
        XCTAssertFalse(zoom.exists)
        XCTAssertEqual(pillOffset, Self.pillOffset, accuracy: 1)
    }

    func testVisibleShowsThreeAndShiftsPills72() {
        launch(buttons: "visible")

        for identifier in Self.buttonIdentifiers { XCTAssertTrue(window.buttons[identifier].exists, identifier) }
        XCTAssertTrue(zoom.exists)
        XCTAssertEqual(pillOffset, Self.shiftedPillOffset, accuracy: 1)
    }

    func testHoverRevealsOnStripAndHidesOutside() {
        launch(buttons: "hover")
        app.element("smalti.terminal").hover()
        waitUntil(close, exists: false)

        app.element("smalti.dragStrip").hover()
        waitUntil(close, exists: true)
        app.element("smalti.terminal").hover()

        waitUntil(close, exists: false)
        XCTAssertEqual(pillOffset, Self.shiftedPillOffset, accuracy: 1)
    }

    /// The close button goes through ⇧⌘W's question; with one window that is quitting.
    func testCloseButtonAsksWithBusyPane() {
        launch(buttons: "visible")
        app.run("sleep 100")
        let header = app.element("smalti.paneHeader")
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'sleep'"), object: header)
        wait(for: [running], timeout: 10)

        close.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["¿Salir de Smalti?"].exists)
        sheet.buttons["Cancelar"].click()
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testZoomButtonZooms() {
        launch(buttons: "visible")
        let before = window.frame

        zoom.click()

        // Zoom fills the visible area below the menu bar; full screen would cover the whole screen.
        let fullHeight = NSScreen.main?.frame.height ?? 0
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [window] _, _ in
                window.frame.width > before.width + 50 && window.frame.height < fullHeight
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [zoomed], timeout: 5), .completed, "frame \(window.frame)")
    }

    /// Block 4 review (I3): AppKit lays the traffic lights out again; they stay centered in the strip at x = 20.
    func testButtonsStayInTheStripAfterResizeAndFullScreen() {
        launch(buttons: "visible")
        zoom.click()
        expectCloseCentered()

        app.typeKey("f", modifierFlags: [.control, .command])
        waitForFullScreen(true)
        app.typeKey("f", modifierFlags: [.control, .command])
        waitForFullScreen(false)

        expectCloseCentered()
        let before = window.frame
        zoom.click()
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [window] _, _ in
                window.frame != before && window.frame.height < (NSScreen.main?.frame.height ?? 0)
            },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [zoomed], timeout: 5), .completed, "green still zooms after full screen")
    }

    /// Block 4 review (I4): full screen hands the buttons to macOS (its own title bar, which accessibility does not
    /// expose while hidden); coming back, `hidden` hides them again.
    func testLeavingFullScreenHidesTheButtonsAgain() {
        launch(buttons: "hidden")

        app.typeKey("f", modifierFlags: [.control, .command])
        waitForFullScreen(true)
        app.typeKey("f", modifierFlags: [.control, .command])
        waitForFullScreen(false)

        waitUntil(close, exists: false)
        XCTAssertEqual(pillOffset, Self.pillOffset, accuracy: 1)
    }

    private func expectCloseCentered() {
        let centered = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                abs(close.frame.midX - window.frame.minX - 20) < 2 && abs(close.frame.midY - window.frame.minY - 20) < 2
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [centered], timeout: 5), .completed,
            "close at \(close.frame), window \(window.frame)")
    }

    /// The glass says " · pantalla completa" while in full screen; one more second for the animation to end.
    private func waitForFullScreen(_ isFullScreen: Bool) {
        let glass = app.element("smalti.glass")
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                ((glass.value as? String) ?? "").hasSuffix(" · pantalla completa") == isFullScreen
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [changed], timeout: 10), .completed, "full screen should be \(isFullScreen)")
        sleep(1)
    }

    /// Block 4 review (M4): switching to `hover` with the cursor already on the strip shows them at once.
    func testSwitchingToHoverWithTheCursorOnTheStripShowsThem() {
        launch(buttons: "hidden")
        app.element("smalti.dragStrip").hover()
        app.writeTheme("[window]\nbuttons = \"hover\"\n")

        app.typeKey("k", modifierFlags: .command)
        app.typeText("recargar")
        app.typeKey(.return, modifierFlags: [])

        waitUntil(close, exists: true)
    }

    func testMinimizeButtonMinimizes() {
        launch(buttons: "visible")

        window.buttons[XCUIIdentifierMinimizeWindow].click()

        let minimized = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: window)
        XCTAssertEqual(XCTWaiter().wait(for: [minimized], timeout: 10), .completed)
    }

    /// C15: with "Reducir movimiento" the buttons are there at once, with no fade (the strip says how it showed them).
    func testReduceMotionSkipsFade() {
        launch(buttons: "hover", reduceMotion: true)
        app.element("smalti.terminal").hover()
        waitUntil(close, exists: false)

        app.element("smalti.dragStrip").hover()

        waitUntil(close, exists: true, timeout: 3)
        XCTAssertEqual(app.element("smalti.dragStrip").value as? String, "botones sin fundido")
    }
}
