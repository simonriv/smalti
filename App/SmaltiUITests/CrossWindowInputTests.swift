import AppKit
import XCTest

/// Final review: the Tab menu and the ⌃R palette are shared by every window, but only their own window's keys are
/// theirs. Two restored windows side by side, so each can be clicked where the other does not cover it.
final class CrossWindowInputTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    override func setUp() async throws {
        try await super.setUp()
        let app = XCUIApplication.isolatedSmaltiWithIntegration()
        let top = (NSScreen.screens.first?.visibleFrame.maxY ?? 900) - 560
        let window = { (x: Double, name: String) in
            SessionState.Window(
                frame: (x: x, y: top, width: 640, height: 500),
                workspaces: [.init(name: name, root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])])
        }
        SessionState.seed(windows: [window(20, "solen"), window(700, "billi")], alwaysRestore: true, in: app)
        launch(app, shells: 2)
        sleep(2)  // zsh's first prompt installs the input script.
    }

    /// Screen frames of the two windows, left one first.
    private var windowFrames: [CGRect] {
        app.windows.matching(identifier: "smalti.window").allElementsBoundByIndex.map(\.frame).sorted {
            $0.minX < $1.minX
        }
    }

    /// Clicks the middle of a window's frame (its terminal), wherever XCUITest's window order is now.
    private func click(_ frame: CGRect) {
        let anchor = app.windows.firstMatch
        let origin = anchor.frame.origin
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).click()
    }

    private func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    func testTabMenuInOneWindowLeavesTheOtherItsReturn() {
        let frames = windowFrames
        guard frames.count == 2 else { return XCTFail("expected two windows, found \(frames.count)") }
        click(frames[0])
        paste("git ch")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))
        click(frames[1])

        app.typeText("<<<otra>\"$SMALTI_UITEST_OUT\"\n")

        waitForOutput("otra\n")
    }

    func testHistoryPaletteInOneWindowLeavesTheOtherItsShortcuts() {
        let frames = windowFrames
        guard frames.count == 2 else { return XCTFail("expected two windows, found \(frames.count)") }
        click(frames[0])
        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        click(frames[1])

        app.typeKey("d", modifierFlags: .command)

        let headers = app.elements("smalti.paneHeader")
        let split = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in headers.count == 3 }, object: nil)
        wait(for: [split], timeout: 5)
    }
}
