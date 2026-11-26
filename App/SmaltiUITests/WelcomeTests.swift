import XCTest

/// F7.7 (C4): the welcome card on a fresh install, completed and skipped by keyboard, never shown to someone who
/// already used Smalti, and reopened from ⌘K and the help.
final class WelcomeTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var card: XCUIElement { app.element("smalti.welcome") }
    private var welcomeMark: URL { app.stateDirectory.appending(path: "welcome.json") }
    private var themeFile: URL { app.configFile.deletingLastPathComponent().appending(path: "theme.toml") }

    private func value(_ identifier: String) -> String { app.element(identifier).value as? String ?? "" }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 10) {
        wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
            timeout: timeout)
    }

    private func themeWritten() -> String { (try? String(contentsOf: themeFile, encoding: .utf8)) ?? "" }

    func testFirstLaunchCompletesByKeyboard() {
        let fresh = XCUIApplication.isolatedSmalti(welcome: true)
        fresh.useFakeClaude(installed: false)
        launch(fresh)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        waitFor { self.value("smalti.welcome.claude").contains("espacio: instalar") }

        app.typeKey(.space, modifierFlags: [])
        waitFor { self.value("smalti.welcome.claude").contains("instalada") }
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        waitFor { self.value("smalti.welcome.theme").contains("Niebla") }
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: welcomeMark.path(percentEncoded: false)))
        waitFor { self.themeWritten().contains(#"theme = "niebla""#) }
    }

    func testEscSkipsAndRestoresTheTheme() {
        launch(XCUIApplication.isolatedSmalti(welcome: true))
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        waitFor { self.value("smalti.welcome.theme").contains("Niebla") }

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: welcomeMark.path(percentEncoded: false)))
        waitFor { !self.themeWritten().contains(#"theme = "niebla""#) }
    }

    func testNotShownToSomeoneWithASavedSession() {
        let returning = XCUIApplication.isolatedSmalti(welcome: true)
        SessionState.seed(
            [SessionState.Workspace(name: "tmp", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")])],
            alwaysRestore: true, in: returning)
        launch(returning)

        XCTAssertFalse(card.waitForExistence(timeout: 3))
        waitFor { FileManager.default.fileExists(atPath: self.welcomeMark.path(percentEncoded: false)) }
    }

    func testReopensFromThePalette() {
        launch(XCUIApplication.isolatedSmalti())
        XCTAssertFalse(card.exists)

        openPalette()
        app.typeText("bienvenida")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    func testReopensFromTheHelp() {
        launch(XCUIApplication.isolatedSmalti())
        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))

        app.typeText("bienvenida")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
}
