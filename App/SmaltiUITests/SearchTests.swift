import XCTest

/// F4.5 C8: ⌘F searches the focused pane's scrollback: "n de m", ⌘G and ⇧⌘G move, esc clears and gives the
/// terminal its keyboard back; the bar closes with its pane, on a pane switch and on a workspace switch.
final class SearchTests: SmaltiUITestCase {
    private var bar: XCUIElement { app.element("smalti.search") }
    private var counter: XCUIElement { app.element("smalti.searchCount") }
    private var terminalText: String { app.element("smalti.terminal").value as? String ?? "" }

    private func printWarnings() {
        app.run("printf 'warn\\nok\\nwarn\\n'")
        let printed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.components(separatedBy: "warn").count >= 4 },
            object: nil)
        wait(for: [printed], timeout: 5)
    }

    private func search(_ text: String) {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        app.typeText(text)
    }

    private func expectCounter(_ matches: @escaping (String) -> Bool, _ description: String) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { [counter] _, _ in matches(counter.value as? String ?? "") }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "\(description): \(counter.value ?? "")")
    }

    private static func position(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: " ")
        guard parts.count == 3, parts[1] == "de", let first = Int(parts[0]), let total = Int(parts[2]) else {
            return nil
        }
        return (first, total)
    }

    func testCommandFFindsAndCounts() {
        printWarnings()

        search("warn")

        expectCounter({ Self.position($0).map { $0.1 >= 2 } ?? false }, "n de m with at least the two outputs")
    }

    func testCommandGAndShiftCommandGNavigate() {
        printWarnings()
        search("warn")
        expectCounter({ Self.position($0) != nil }, "a position")
        let start = Self.position(counter.value as? String ?? "")?.0

        app.typeKey("g", modifierFlags: .command)
        expectCounter({ Self.position($0)?.0 != start }, "moved forward")
        app.typeKey("g", modifierFlags: [.command, .shift])

        expectCounter({ Self.position($0)?.0 == start }, "back where it started")
    }

    func testNoMatchesSaysSinResultados() {
        search("zzqx-no-esta")

        expectCounter({ $0 == "Sin resultados" }, "no matches")
    }

    func testEscapeClearsAndReturnsTheKeyboard() {
        printWarnings()
        search("warn")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        app.typeText("echo busqueda-cerrada\n")
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("busqueda-cerrada") }, object: nil)
        wait(for: [typed], timeout: 5)
    }

    func testKeysGoToTheFieldWhileOpen() {
        search("solo-en-el-campo")

        XCTAssertEqual(app.element("smalti.searchField").value as? String, "solo-en-el-campo")
        XCTAssertFalse(terminalText.contains("solo-en-el-campo"))
    }

    /// Review Focus 4: the bar never outlives its pane.
    func testSearchClosesWhenItsPaneCloses() {
        app.run("sleep 2; exit")
        search("x")

        XCTAssertTrue(bar.waitForNonExistence(timeout: 10))
    }

    func testSearchClosesOnAPaneSwitch() {
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)
        search("x")

        app.elements("smalti.terminal").element(boundBy: 0).click()

        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }

    func testSearchClosesOnAWorkspaceSwitch() {
        search("x")

        app.element("smalti.newWorkspace").click()

        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }
}
