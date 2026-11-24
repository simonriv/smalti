import Carbon
import XCTest

/// F4.5 C1, C2, C13, C15: the macOS menus come from the keymap, every item runs its command once, the terminal has a
/// context menu, "Acerca de" names the build, ⌘, opens the TOML and the secure-entry item toggles it.
final class MenuTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var openLog: URL { outputFile.appendingPathExtension("opened") }

    private func launchWithOpenLog() {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiOpenLog", openLog.path(percentEncoded: false)]
        launch(app)
    }

    private func menu(_ title: String) -> XCUIElement { app.menuBars.menuBarItems[title] }

    private func click(_ item: String, in title: String) {
        menu(title).click()
        app.menuBars.menuItems[item].click()
    }

    func testMenuBarHasTheSpecMenusInOrder() {
        launchWithOpenLog()

        let titles = app.menuBars.firstMatch.children(matching: .menuBarItem).allElementsBoundByIndex.map(\.title)

        XCTAssertEqual(Array(titles.suffix(5)), ["Archivo", "Edición", "Ver", "Ventana", "Ayuda"])
    }

    func testMenuItemRunsItsCommandOnce() {
        launchWithOpenLog()

        click("Nuevo panel", in: "Archivo")

        waitForShells(count: 2)
        XCTAssertEqual(app.elements("smalti.paneHeader").count, 2)
    }

    func testEditMenuHasDictationAndEmojiOnce() {
        launchWithOpenLog()
        menu("Edición").click()

        XCTAssertEqual(app.menuBars.menuItems.matching(identifier: "smalti.menu.emoji").count, 1)
        XCTAssertEqual(app.menuBars.menuItems.matching(identifier: "smalti.menu.dictation").count, 1)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testRightClickShowsTheTerminalContextMenu() {
        launchWithOpenLog()

        app.element("smalti.terminal").rightClick()

        XCTAssertTrue(app.menus.menuItems["Copiar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menus.menuItems["Nuevo panel"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testAboutShowsVersionAndCommit() {
        launchWithOpenLog()

        click(
            "Acerca de Smalti", in: app.menuBars.firstMatch.children(matching: .menuBarItem).element(boundBy: 1).title)

        let version = app.staticTexts.matching(NSPredicate(format: "value CONTAINS '0.5.0 ('")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
    }

    func testConfigOpenCreatesTheTemplateWhenMissing() throws {
        launchWithOpenLog()
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.configFile.path(percentEncoded: false)))

        // F5: "Abrir config.toml" is ⌥⌘, (⌘, opens Apariencia).
        app.typeKey(",", modifierFlags: [.option, .command])

        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate { [openLog] _, _ in
                FileManager.default.fileExists(atPath: openLog.path(percentEncoded: false))
            },
            object: nil)
        wait(for: [opened], timeout: 5)
        let template = try String(contentsOf: app.configFile, encoding: .utf8)
        XCTAssertTrue(template.contains("# font_size = "))
        XCTAssertEqual(
            try String(contentsOf: openLog, encoding: .utf8).trimmingCharacters(in: .newlines),
            app.configFile.path(percentEncoded: false))
    }

    func testSecureInputItemTogglesSecureEntry() throws {
        try XCTSkipIf(IsSecureEventInputEnabled(), "another app holds secure entry; the system-wide flag cannot tell")
        launchWithOpenLog()
        let smalti = app.menuBars.firstMatch.children(matching: .menuBarItem).element(boundBy: 1).title

        click("Entrada de teclado segura", in: smalti)
        let on = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in IsSecureEventInputEnabled() }, object: nil)
        wait(for: [on], timeout: 5)

        click("Entrada de teclado segura", in: smalti)
        let off = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !IsSecureEventInputEnabled() }, object: nil)
        wait(for: [off], timeout: 5)
    }

    /// Block 3 review: ⌘N during "Retomar donde quedaste" opens a window; "Empezar limpio" still starts the one that
    /// asked, so both have a pane.
    func testNewWindowDuringTheResumeScreenDoesNotStealStartClean() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [.init(name: "solen", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])],
            alwaysRestore: false, in: app)
        self.app = app
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))

        app.typeKey("n", modifierFlags: .command)
        waitForShells(count: 1)
        // The asking window is in the back now: a click on its empty top edge brings it forward, then esc is
        // "Empezar limpio" (a first click on a button of a window in the back only activates it).
        app.element("smalti.restore").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).click()
        app.typeKey(.escape, modifierFlags: [])

        waitForShells(count: 2)
    }
}
