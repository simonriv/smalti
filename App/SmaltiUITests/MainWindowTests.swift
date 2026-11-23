import XCTest

/// A5 (window part): the glass window matches the design tokens of docs/design/README.md.
final class MainWindowTests: SmaltiUITestCase {
    private var window: XCUIElement { app.windows["smalti.window"] }

    /// F2 part A: every UI test launch keeps its sessions in a temporary state directory, never the user's.
    func testLaunchUsesIsolatedStateDirectory() {
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.value as? String, app.stateDirectory.path(percentEncoded: false))
    }

    func testWindowHasDesignSize() {
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.size, CGSize(width: 1328, height: 820))
    }

    func testTrafficLightsAreHidden() {
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        for identifier in [XCUIIdentifierCloseWindow, XCUIIdentifierMinimizeWindow, XCUIIdentifierFullScreenWindow] {
            let button = window.buttons[identifier]
            XCTAssertFalse(button.exists && button.isHittable, "\(identifier) is visible")
        }
    }

    func testDragStripIs40PointsTall() {
        let strip = app.element("smalti.dragStrip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(strip.frame.height, 40)
    }

    func testPaneIsInsetByAreaPadding() {
        let pane = app.element("smalti.pane")
        let strip = app.element("smalti.dragStrip")
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        XCTAssertEqual(pane.frame.minX - window.frame.minX, 10)
        XCTAssertEqual(pane.frame.minY - strip.frame.maxY, 10)
        XCTAssertEqual(window.frame.maxX - pane.frame.maxX, 10)
        XCTAssertEqual(app.element("smalti.statusBar").frame.minY - pane.frame.maxY, 10)
    }

    /// Main.dc.html footer: 28 pt, flush with the bottom of the window.
    func testStatusBarIs28PointsAtTheBottom() {
        let statusBar = app.element("smalti.statusBar")
        XCTAssertTrue(statusBar.waitForExistence(timeout: 5))
        XCTAssertEqual(statusBar.frame.height, 28)
        XCTAssertEqual(statusBar.frame.maxY, window.frame.maxY)
    }
}
