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

    private func markExists() -> Bool {
        FileManager.default.fileExists(atPath: welcomeMark.path(percentEncoded: false))
    }

    /// More than `ChangeAppearance.saveDelay` (300 ms): a deferred write has had its chance.
    private func outlastTheSaveDelay() {
        let later = expectation(description: "after the save delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { later.fulfill() }
        wait(for: [later], timeout: 3)
    }

    /// The card on its theme row, with Niebla previewed and already written by the preview.
    private func previewNiebla() {
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        waitFor { self.value("smalti.welcome.theme").contains("Niebla") }
        waitFor { self.themeWritten().contains(#"theme = "niebla""#) }
    }

    /// The card's mean brightness (0–1), from its screenshot drawn into one pixel.
    private func brightness(of element: XCUIElement) -> Double {
        let screenshot = element.screenshot().image
        guard let image = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return 0 }
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

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
        XCTAssertTrue(markExists())
        waitFor { self.themeWritten().contains(#"theme = "niebla""#) }
        outlastTheSaveDelay()
        XCTAssertTrue(themeWritten().contains(#"theme = "niebla""#), "↩ keeps the chosen theme")
    }

    func testEscSkipsAndRestoresTheTheme() {
        launch(XCUIApplication.isolatedSmalti(welcome: true))
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        previewNiebla()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(markExists())
        waitFor { self.themeWritten().contains(#"theme = "obsidiana""#) }
    }

    func testAClickBehindKeepsTheKeyboardOnTheCard() {
        launch(XCUIApplication.isolatedSmalti(welcome: true))
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        app.element("smalti.terminal").click()
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(markExists())
    }

    func testAFailedInstallSaysWhy() throws {
        let fresh = XCUIApplication.isolatedSmalti(welcome: true)
        let script = fresh.useFakeClaude(installed: false).deletingLastPathComponent().appending(path: "fake-claude")
        let failing = try String(contentsOf: script, encoding: .utf8).replacingOccurrences(
            of: #""plugin install smalti@smalti") touch "$state" ;;"#,
            with: #""plugin install smalti@smalti") echo "sin red" >&2; exit 1 ;;"#)
        try failing.write(to: script, atomically: true, encoding: .utf8)
        launch(fresh)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        waitFor { self.value("smalti.welcome.claude").contains("espacio: instalar") }

        app.typeKey(.space, modifierFlags: [])

        waitFor({ self.value("smalti.welcome.claude").contains("sin red") }, timeout: 8)
    }

    func testClosingTheWindowPutsTheThemeBackWithoutMarking() {
        launch(XCUIApplication.isolatedSmalti(config: "[window]\nbuttons = \"visible\"\n", welcome: true))
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        previewNiebla()

        app.windows.matching(identifier: "smalti.window").firstMatch.buttons[XCUIIdentifierCloseWindow].click()

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        waitFor { self.themeWritten().contains(#"theme = "obsidiana""#) }
        XCTAssertFalse(markExists())
    }

    func testOpenedByHandWritesNoMark() throws {
        launch(XCUIApplication.isolatedSmalti())
        try FileManager.default.removeItem(at: welcomeMark)
        openPalette()
        app.typeText("bienvenida")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        outlastTheSaveDelay()
        XCTAssertFalse(markExists())
    }

    func testTheCardTakesThePreviewedTheme() {
        let reference = XCUIApplication.isolatedSmalti(welcome: true)
        reference.writeTheme("[appearance]\ntheme = \"niebla\"\n")
        launch(reference)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        outlastTheSaveDelay()
        let niebla = brightness(of: card)
        app.terminate()

        launch(XCUIApplication.isolatedSmalti(welcome: true))
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let obsidiana = brightness(of: card)
        previewNiebla()
        outlastTheSaveDelay()

        let previewed = brightness(of: card)
        XCTAssertEqual(previewed, niebla, accuracy: abs(niebla - obsidiana) / 4, "obsidiana \(obsidiana)")
    }

    func testOneCardForTheWholeApp() {
        launch(XCUIApplication.isolatedSmalti())
        app.typeKey("n", modifierFlags: .command)
        let windows = app.windows.matching(identifier: "smalti.window")
        waitFor { windows.count == 2 }
        openPalette()
        app.typeText("bienvenida")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        windows.allElementsBoundByIndex.first { !$0.descendants(matching: .any)["smalti.welcome"].exists }?.click()
        openPalette()
        app.typeText("bienvenida")
        app.typeKey(.return, modifierFlags: [])

        outlastTheSaveDelay()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "smalti.welcome").count, 1)
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
