import AppKit
import XCTest

/// Saves every item of the user's general pasteboard, with all its types and data, and puts it back afterwards
/// (R9). Tests create it in setUp and call `restore()` in tearDown, which XCTest runs even when a test fails.
final class PasteboardGuard {
    /// Each item's types in their original order, with their data.
    private let saved: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init() {
        saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type: type, data: $0) } }
        }
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = saved.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { item.setData($0.data, forType: $0.type) }
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

    /// Subclasses whose tests each need their own launch (a fixture config) return false and call `launch(_:)`.
    var launchesAtSetUp: Bool { true }

    override func setUp() async throws {
        continueAfterFailure = false
        pasteboard = PasteboardGuard()
        outputFile = FileManager.default.temporaryDirectory.appending(path: "smalti-uitest-\(UUID().uuidString)")
        if launchesAtSetUp { launch(.isolatedSmalti()) }
    }

    override func tearDown() async throws {
        if let app {
            app.terminate()
            try? FileManager.default.removeItem(at: app.configFile.deletingLastPathComponent())
        }
        pasteboard.restore()
        try? FileManager.default.removeItem(at: outputFile)
    }

    /// Launches `app` (built by `isolatedSmalti`) and waits for its first shell.
    func launch(_ app: XCUIApplication) {
        self.app = app
        app.launchEnvironment["SMALTI_UITEST_OUT"] = outputFile.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.element("smalti.terminal").waitForExistence(timeout: 10))
        waitForShells(count: 1)
    }

    func openPalette() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.palette").waitForExistence(timeout: 5))
    }

    /// "Recargar configuración" from the palette, typed without spaces.
    func reloadConfigFromPalette() {
        openPalette()
        app.typeText("recargar")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    func waitForOutput(_ expected: String, timeout: TimeInterval = 10) {
        let file = outputFile!
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (try? String(contentsOf: file, encoding: .utf8)) == expected },
            object: nil)
        wait(for: [written], timeout: timeout)
    }

    /// Every pane header names `zsh`: each shell is at its prompt and ready for input.
    func waitForShells(count: Int, timeout: TimeInterval = 10) {
        let headers = app.elements("smalti.paneHeader")
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                headers.count == count && headers.allElementsBoundByIndex.allSatisfy { $0.label == "zsh" }
            }, object: nil)
        wait(for: [ready], timeout: timeout)
    }

    func expect(_ element: XCUIElement, value: String, timeout: TimeInterval = 5) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (element.value as? String ?? "") == value }, object: nil)
        wait(for: [matched], timeout: timeout)
    }

    func waitForPaneCount(_ count: Int, timeout: TimeInterval = 10) {
        let query = app.elements("smalti.pane")
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in query.count == count }, object: nil)
        wait(for: [matched], timeout: timeout)
    }
}

/// Simón's login shell attaches to `tmux main`; isolated panes must never add clients to it (R1, B13).
enum TmuxClients {
    private static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    /// Attached clients of the user's tmux server, or nil when tmux is missing or no server runs.
    static func count() -> Int? {
        guard let tmux = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: tmux)
        process.arguments = ["list-clients"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").count
    }
}
