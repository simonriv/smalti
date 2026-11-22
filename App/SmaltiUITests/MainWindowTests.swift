import XCTest

/// A5 (window part): the glass window matches the design tokens of docs/design/README.md.
final class MainWindowTests: XCTestCase {
    private var app: XCUIApplication!  // Assigned in setUp before every test; XCTest has no init-time setup.

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.isolatedSmalti()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    private var window: XCUIElement { app.windows["smalti.window"] }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
        let strip = element("smalti.dragStrip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(strip.frame.height, 40)
    }

    func testPaneIsInsetByAreaPadding() {
        let pane = element("smalti.pane")
        let strip = element("smalti.dragStrip")
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        XCTAssertEqual(pane.frame.minX - window.frame.minX, 10)
        XCTAssertEqual(pane.frame.minY - strip.frame.maxY, 10)
        XCTAssertEqual(window.frame.maxX - pane.frame.maxX, 10)
        XCTAssertEqual(window.frame.maxY - pane.frame.maxY, 10)
    }
}
