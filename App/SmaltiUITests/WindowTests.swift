import AppKit
import XCTest

/// F4.5 C4–C6: several windows, each with its own workspaces, saved and restored per window; native full screen.
final class WindowTests: SmaltiUITestCase {
    private var windows: XCUIElementQuery { app.windows.matching(identifier: "smalti.window") }

    private func waitForWindows(_ count: Int, timeout: TimeInterval = 10) {
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate { [windows] _, _ in windows.count == count }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [counted], timeout: timeout), .completed, "expected \(count) windows")
    }

    private func status(of window: XCUIElement) -> String {
        window.descendants(matching: .any)["smalti.statusBar"].value as? String ?? ""
    }

    private func expectStatus(_ window: XCUIElement, _ text: String) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in status(of: window).hasPrefix(text) }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "status is \(status(of: window))")
    }

    // MARK: - C4

    /// `zsh -f` reports no directory changes (no OSC 7), so the focused pane's directory is the one it opened in.
    func testCommandNOpensASecondWindowInTheFocusedDirectory() {
        let first = app.element("smalti.paneHeader").value as? String

        app.typeKey("n", modifierFlags: .command)

        waitForWindows(2)
        waitForShells(count: 2)
        let headers = app.elements("smalti.paneHeader").allElementsBoundByIndex
        XCTAssertNotNil(first)
        XCTAssertEqual(headers.map { $0.value as? String }, [first, first])
    }

    func testEachWindowHasItsOwnWorkspacesAndPanes() {
        app.typeKey("n", modifierFlags: .command)
        waitForWindows(2)
        waitForShells(count: 2)

        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 3)
        // The new workspace hides the front window's first one: its two panes stop showing.
        app.typeKey("n", modifierFlags: [.control, .command])
        let front = windows.element(boundBy: 0)
        let pills = front.descendants(matching: .any).matching(identifier: "smalti.workspace")
        let two = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in pills.count == 2 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: 10), .completed)

        let back = windows.element(boundBy: 1)
        XCTAssertEqual(back.descendants(matching: .any).matching(identifier: "smalti.workspace").count, 1)
        XCTAssertTrue(status(of: back).contains("1 panel"), "back window: \(status(of: back))")
    }

    func testShiftCommandWClosesOnlyTheFrontWindow() {
        app.typeKey("n", modifierFlags: .command)
        waitForWindows(2)

        app.typeKey("w", modifierFlags: [.shift, .command])

        waitForWindows(1)
        XCTAssertEqual(app.state, .runningForeground)
        waitForShells(count: 1)
    }

    /// Closing the last window is ⌘Q: the app quits and the session is saved as format 2.
    func testClosingTheLastWindowQuitsAndSavesIt() throws {
        app.typeKey("w", modifierFlags: [.shift, .command])

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let saved = try String(contentsOf: app.stateDirectory.appending(path: "session.json"), encoding: .utf8)
        XCTAssertTrue(saved.contains("\"version\" : 2"))
        XCTAssertTrue(saved.contains("\"windows\""))
    }

    // MARK: - C6

    func testControlCommandFTogglesNativeFullScreen() {
        let window = windows.element(boundBy: 0)
        let normal = window.frame.size
        // Full screen fills the screen's width; on a display with a notch the strip beside it stays outside.
        let screen = NSScreen.screens.first?.frame.size ?? .zero
        let notch = NSScreen.screens.first?.safeAreaInsets.top ?? 0

        app.typeKey("f", modifierFlags: [.control, .command])
        let entered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                window.frame.width == screen.width && window.frame.height >= screen.height - notch - 1
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [entered], timeout: 10), .completed, "frame \(window.frame)")

        app.typeKey("f", modifierFlags: [.control, .command])
        let left = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.frame.size == normal }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [left], timeout: 10), .completed, "frame \(window.frame)")
    }

    // MARK: - C5

    func testTwoWindowsRestoreGroupedWithTheirFrames() {
        app.terminate()
        let relaunched = XCUIApplication.isolatedSmalti()
        let mainHeight = NSScreen.screens.first?.frame.height ?? 900
        SessionState.seed(
            windows: [
                .init(
                    frame: (x: 40, y: mainHeight - 640, width: 900, height: 600),
                    workspaces: [
                        .init(name: "solen", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])
                    ]),
                .init(
                    frame: (x: 300, y: mainHeight - 760, width: 820, height: 560),
                    workspaces: [
                        .init(name: "billi", root: "/usr", layout: "columns", panes: [.init(directory: "/usr")]),
                        .init(name: "rizaria", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")]),
                    ]),
            ], frontIndex: 1, alwaysRestore: false, in: relaunched)
        self.app = relaunched
        relaunched.launch()
        XCTAssertTrue(relaunched.element("smalti.restore").waitForExistence(timeout: 10))
        let groups = relaunched.elements("smalti.resumeWindow").allElementsBoundByIndex.map { $0.value as? String }
        XCTAssertEqual(groups, ["VENTANA 1 · 1 WORKSPACE", "VENTANA 2 · 2 WORKSPACES"])

        relaunched.typeKey(.return, modifierFlags: [])

        waitForWindows(2)
        // "rizaria" is the second window's hidden workspace: two panes show.
        waitForShells(count: 2)
        let front = windows.element(boundBy: 0)
        XCTAssertEqual(front.frame.width, 820, accuracy: 2)
        XCTAssertEqual(front.frame.minX, 300, accuracy: 2)
        XCTAssertEqual(front.descendants(matching: .any).matching(identifier: "smalti.workspace").count, 2)
    }

    func testFormatOneSessionOpensAsOneWindow() {
        app.terminate()
        let relaunched = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [.init(name: "solen", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])],
            alwaysRestore: true, in: relaunched)

        launch(relaunched)

        waitForWindows(1)
        expectStatus(windows.element(boundBy: 0), "solen")
    }
}
