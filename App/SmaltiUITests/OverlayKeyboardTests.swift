import AppKit
import XCTest

/// Block 4 review: one overlay at a time, so the keyboard always comes back; the feedback box keeps ⌘V away from
/// the terminal; the Window menu lists every window.
final class OverlayKeyboardTests: SmaltiUITestCase {
    private var terminalText: String { app.element("smalti.terminal").value as? String ?? "" }

    private func expectTyping(reachesTheTerminal marker: String) {
        app.typeText("echo \(marker)\n")
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText.contains("\(marker)\n") }, object: nil)
        wait(for: [typed], timeout: 5)
    }

    func testPaletteOverTheSearchGivesTheKeyboardBack() {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.search").waitForExistence(timeout: 5))
        openPalette()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.element("smalti.search").exists)
        expectTyping(reachesTheTerminal: "tras-la-busqueda")
    }

    func testPaletteOverTheHelpGivesTheKeyboardBack() {
        app.typeKey("?", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))
        openPalette()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertFalse(app.element("smalti.help").exists)
        expectTyping(reachesTheTerminal: "tras-la-ayuda")
    }

    func testCommandVWithTheFeedbackOpenDoesNotPasteIntoTheTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("no-debe-pegarse", forType: .string)
        openPalette()
        app.typeText("reportar")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.feedback").waitForExistence(timeout: 5))

        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.feedback").waitForNonExistence(timeout: 5))
        XCTAssertFalse(terminalText.contains("no-debe-pegarse"))
    }

    /// Final review: the menu follows the keyboard's rules; with the search bar open, the observatory is not offered.
    func testMenuFollowsTheSearchBar() {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.search").waitForExistence(timeout: 5))

        app.menuBars.menuBarItems["Ver"].click()

        XCTAssertFalse(app.menuBars.menuItems["Observatorio"].isEnabled)
        XCTAssertTrue(app.menuBars.menuItems["Paleta de comandos"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Final review: `[keys]` needs the ids, and the help shows them while filtering.
    func testHelpShowsCommandIdsWhileFiltering() {
        app.typeKey("?", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("smalti.helpCommandName").exists)

        app.typeText("window.new")

        let name = app.elements("smalti.helpCommandName").firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "window.new")
        XCTAssertEqual(app.elements("smalti.helpRow").count, 1)
    }

    func testTheWindowMenuListsEveryWindow() {
        app.typeKey("n", modifierFlags: .command)
        waitForShells(count: 2)
        let title = app.windows.matching(identifier: "smalti.window").firstMatch.title

        app.menuBars.menuBarItems["Ventana"].click()

        // AppKit's window items carry no identifier; Smalti's own ("Workspace ▸ srivera") do.
        let listed = app.menuBars.menuItems.matching(
            NSPredicate(format: "title == %@ AND NOT (identifier BEGINSWITH 'smalti.')", title))
        XCTAssertEqual(listed.count, 2, "Ventana lists \(listed.count) windows titled \(title)")
        app.typeKey(.escape, modifierFlags: [])
    }
}
