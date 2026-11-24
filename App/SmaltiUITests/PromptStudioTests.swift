import XCTest

/// F5 C1, C4, C11, C12 and C13: the prompt studio (`Prompt.dc.html`) edits a draft, "Aplicar a todos los paneles"
/// writes `theme.toml` and reaches the open shells, and the export writes `starship.toml` where the test says.
final class PromptStudioTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var studio: XCUIElement { app.element("smalti.studio") }
    private var themeFile: URL { app.configFile.deletingLastPathComponent().appending(path: "theme.toml") }
    private var exportFolder: URL { app.configFile.deletingLastPathComponent().appending(path: "export") }

    private func control(_ name: String) -> XCUIElement { app.element("smalti.studio.\(name)") }

    private func launchStudio(nerdFont: Bool = true) {
        let smalti = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
        smalti.launchArguments += [
            "-SmaltiExportDirectory",
            smalti.configFile.deletingLastPathComponent().appending(path: "export")
                .path(percentEncoded: false),
            "-SmaltiNerdFontAvailable", nerdFont ? "YES" : "NO",
        ]
        launch(smalti)
        sleep(2)  // zsh's first prompt installs the prompt script.
        app.typeKey("p", modifierFlags: [.shift, .command])
        XCTAssertTrue(studio.waitForExistence(timeout: 5))
    }

    private func themeText() -> String { (try? String(contentsOf: themeFile, encoding: .utf8)) ?? "" }
    private func terminalText() -> String { app.element("smalti.terminal").value as? String ?? "" }

    private func expectValue(_ element: XCUIElement, _ value: String) {
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: 5), .completed, "value is \(element.value ?? "nil")")
    }

    private func expectThemeFile(contains lines: [String]) {
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in lines.allSatisfy { themeText().contains($0) } }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [written], timeout: 5), .completed, "theme.toml:\n\(themeText())")
    }

    private func moduleOrder() -> [String] {
        app.elements("smalti.studio.module").allElementsBoundByIndex.map(\.label)
    }

    // MARK: - C1

    func testEveryStudioControlWritesThemeToml() {
        launchStudio()

        control("template.pills").click()
        control("module.time.toggle").click()
        control("module.runtime.toggle").click()
        control("icons.none").click()
        control("symbol.λ").click()
        control("shellPrompt").click()
        control("apply").click()

        expectThemeFile(contains: [
            "source = \"shell\"", "style = \"pills\"", "layout = \"one-line\"", "icons = \"none\"", "symbol = \"λ\"",
            "modules = [\"directory\", \"git-branch\", \"git-status\", \"duration\", \"agents\", \"time\"]",
        ])
    }

    func testTemplateCardFollowsLayout() {
        launchStudio()
        expectValue(control("template.cleanLine"), "seleccionado")

        control("layout").click()

        expectValue(control("template.singleLine"), "seleccionado")
    }

    /// ⌘↑ and ⌘↓ move the focused active module (dragging does the same; XCUITest's drags never reach the window
    /// here, so it is checked by hand).
    func testKeyboardReordersModules() {
        launchStudio()

        app.elements("smalti.studio.module").element(boundBy: 0).click()
        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertEqual(Array(moduleOrder().prefix(2)), ["Rama git", "Directorio"])

        app.elements("smalti.studio.module").element(boundBy: 1).click()
        app.typeKey(.upArrow, modifierFlags: .command)

        XCTAssertEqual(Array(moduleOrder().prefix(2)), ["Directorio", "Rama git"])
    }

    // MARK: - C12

    func testApplyUpdatesOpenShells() {
        launchStudio()

        control("symbol.λ").click()
        control("apply").click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(studio.waitForNonExistence(timeout: 5))

        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in terminalText().contains("λ") }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, terminalText())
    }

    func testDraftDoesNotChangeShellsBeforeApply() {
        launchStudio()

        control("symbol.λ").click()
        sleep(2)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(studio.waitForNonExistence(timeout: 5))

        XCTAssertFalse(terminalText().contains("λ"), terminalText())
        XCTAssertFalse(themeText().contains("symbol = \"λ\""))
    }

    // MARK: - C11

    func testExportWritesStarshipToTempDestination() throws {
        launchStudio()

        control("export").click()

        let file = exportFolder.appending(path: "starship.toml")
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [written], timeout: 5), .completed)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("[character]"))
    }

    func testNerdFontOptionDisabledWithoutNerdFont() {
        launchStudio(nerdFont: false)

        XCTAssertFalse(control("icons.nerd").isEnabled)
        XCTAssertTrue(app.staticTexts["No hay una Nerd Font instalada"].exists)
    }

    // MARK: - C13 and C4

    func testShiftCmdPOpensStudio() {
        launchStudio()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(studio.waitForNonExistence(timeout: 5))
    }

    func testStudioMatchesBoardCapture() throws {
        launchStudio()

        let captures = FileManager.default.temporaryDirectory.appending(path: "smalti-captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let window = app.windows.matching(identifier: "smalti.window").firstMatch
        try window.screenshot().pngRepresentation.write(to: captures.appending(path: "f5-prompt.png"))

        XCTAssertEqual(studio.frame.width, window.frame.width, accuracy: 2)
        XCTAssertEqual(control("aside").frame.width, 400, accuracy: 1)
    }
}
