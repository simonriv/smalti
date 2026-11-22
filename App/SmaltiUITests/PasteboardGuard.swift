import AppKit
import XCTest

/// Saves every item of the user's general pasteboard, with all its types and data, and puts it back afterwards
/// (R9). Tests create it in setUp and call `restore()` in tearDown, which XCTest runs even when a test fails.
final class PasteboardGuard {
    private let saved: [[NSPasteboard.PasteboardType: Data]]

    init() {
        saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = saved.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { type, data in item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

extension XCUIApplication {
    /// Runs a one-line command in the focused terminal. XCUITest types " " as ⌃Space on the Latin American layout,
    /// so the line is pasted (⌘V) and only the newline is typed. Callers own a `PasteboardGuard`.
    func run(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        typeKey("v", modifierFlags: .command)
        typeText("\n")
    }

    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }

    func elements(_ identifier: String) -> XCUIElementQuery {
        descendants(matching: .any).matching(identifier: identifier)
    }
}

/// A launched, isolated Smalti whose shells write to a per-test file through `$SMALTI_UITEST_OUT`.
@MainActor
class SmaltiUITestCase: XCTestCase {
    var app: XCUIApplication!  // Set in setUp before every test; XCTest has no init-time setup.
    var outputFile: URL!  // Same: created per test.
    private var pasteboard: PasteboardGuard!  // Same: saved per test, restored in tearDown.

    override func setUp() async throws {
        continueAfterFailure = false
        pasteboard = PasteboardGuard()
        outputFile = FileManager.default.temporaryDirectory.appending(path: "smalti-uitest-\(UUID().uuidString)")
        app = XCUIApplication.isolatedSmalti()
        app.launchEnvironment["SMALTI_UITEST_OUT"] = outputFile.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.element("smalti.terminal").waitForExistence(timeout: 10))
        sleep(2)  // Let zsh print its first prompt before typing.
    }

    override func tearDown() async throws {
        app.terminate()
        pasteboard.restore()
        try? FileManager.default.removeItem(at: outputFile)
    }

    func waitForOutput(_ expected: String, timeout: TimeInterval = 10) {
        let file = outputFile!
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (try? String(contentsOf: file, encoding: .utf8)) == expected },
            object: nil)
        wait(for: [written], timeout: timeout)
    }

    func waitForPaneCount(_ count: Int, timeout: TimeInterval = 10) {
        let query = app.elements("smalti.pane")
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in query.count == count }, object: nil)
        wait(for: [matched], timeout: timeout)
    }
}
