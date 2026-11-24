import AppKit
import XCTest

/// F5 C1, C13 and C14: the Appearance panel (`Apariencia.dc.html`) writes `theme.toml`, shows what is written there by
/// hand, never touches `config.toml`, and keeps the panes alive beside it.
final class AppearanceTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    /// What a click on an ANSI swatch picks instead of opening the system color panel (`-SmaltiPickedColor`).
    private static let pickedColor = "#ff6b6b"
    private static let panelWidth: CGFloat = 440

    private var panel: XCUIElement { app.element("smalti.appearance") }
    private var themeFile: URL { app.configFile.deletingLastPathComponent().appending(path: "theme.toml") }

    private func control(_ name: String) -> XCUIElement { app.element("smalti.appearance.\(name)") }

    private func launchIsolated(config: String? = nil, theme: String? = nil, extra: [String] = []) {
        let smalti = XCUIApplication.isolatedSmalti(config: config)
        smalti.launchArguments += ["-SmaltiPickedColor", Self.pickedColor] + extra
        if let theme { smalti.writeTheme(theme) }
        launch(smalti)
    }

    private func openPanel() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
    }

    private func themeText() -> String { (try? String(contentsOf: themeFile, encoding: .utf8)) ?? "" }

    /// Waits for the 300 ms save and for every line to be in the file.
    private func expectThemeFile(contains lines: [String], timeout: TimeInterval = 5) {
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in lines.allSatisfy { themeText().contains($0) } }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [written], timeout: timeout), .completed, "theme.toml:\n\(themeText())")
    }

    /// Sliders report numbers, the other controls strings: both read as text.
    private func text(of element: XCUIElement) -> String { element.value.map { "\($0)" } ?? "" }
    private func number(of element: XCUIElement) -> Int { Int((Double(text(of: element)) ?? 0).rounded()) }

    private func expectValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in text(of: element) == value }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [matched], timeout: timeout), .completed, "value is \(element.value ?? "nil")")
    }

    // MARK: - C1

    func testEveryControlWritesThemeToml() {
        launchIsolated()
        openPanel()

        control("theme.bosque").click()
        control("opacity").click()
        app.typeKey(.rightArrow, modifierFlags: [])
        control("blur").click()
        app.typeKey(.leftArrow, modifierFlags: [])
        control("legibility").click()
        control("ansi.1").click()
        control("buttons.visible").click()
        control("fontSize").incrementArrows.firstMatch.click()
        control("gap").incrementArrows.firstMatch.click()
        control("radius").incrementArrows.firstMatch.click()
        control("fontFamily").click()
        app.menuItems["Menlo"].click()

        let opacity = number(of: control("opacity"))
        let blur = number(of: control("blur"))
        expectThemeFile(contains: [
            "theme = \"bosque\"", "glass_opacity = \(Double(opacity) / 100)", "blur = \(blur)",
            "protect_legibility = false", "font_family = \"Menlo\"", "font_size = 14", "gap = 9", "radius = 12",
            "[appearance.ansi.bosque]", "1 = \"\(Self.pickedColor)\"", "buttons = \"visible\"",
        ])
    }

    func testHandEditShowsInPanelAfterReload() {
        launchIsolated()
        openPanel()
        app.writeTheme("[appearance]\ntheme = \"niebla\"\nglass_opacity = 0.8\n\n[window]\nbuttons = \"hover\"\n")

        reloadConfigFromPalette()

        expectValue(control("theme.niebla"), "seleccionado")
        expectValue(control("opacity"), "80")
        expectValue(control("buttons.hover"), "seleccionado")
    }

    // MARK: - C14

    func testConfigTomlHashUnchanged() throws {
        let config = "# mine\n[appearance]\nfont_size = 13\n"
        launchIsolated(config: config)
        openPanel()

        control("theme.niebla").click()
        control("legibility").click()
        control("gap").incrementArrows.firstMatch.click()
        expectThemeFile(contains: ["theme = \"niebla\"", "gap = 9"])

        XCTAssertEqual(try String(contentsOf: app.configFile, encoding: .utf8), config)
    }

    func testDuplicatedKeyWarningShown() {
        launchIsolated(config: "[appearance]\nblur = 10\n", theme: "[appearance]\nblur = 20\n")

        reloadConfigFromPalette()

        let status = app.element("smalti.statusBar")
        let warned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (status.value as? String ?? "").hasPrefix("theme.toml manda sobre config.toml en: ")
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [warned], timeout: 5), .completed, "status: \(status.value ?? "")")
    }

    // MARK: - C13

    func testCommaOpensAndEscCloses() {
        launchIsolated()

        openPanel()
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }

    func testOptionCommaOpensConfigToml() {
        let log = outputFile.deletingLastPathComponent().appending(path: "open-\(UUID().uuidString).log")
        launchIsolated(extra: ["-SmaltiOpenLog", log.path(percentEncoded: false)])

        app.typeKey(",", modifierFlags: [.option, .command])

        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? String(contentsOf: log, encoding: .utf8))?.contains("config.toml") == true
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 5), .completed)
        XCTAssertFalse(panel.exists)
        try? FileManager.default.removeItem(at: log)
    }

    // MARK: - Layout and keyboard

    func testPaneAreaShrinksAndStaysLive() {
        launchIsolated()
        let pane = app.element("smalti.pane")
        let before = pane.frame.width

        openPanel()

        let shrunk = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in pane.frame.width < before - Self.panelWidth + 20 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shrunk], timeout: 5), .completed, "pane \(pane.frame.width)")
        XCTAssertEqual(panel.frame.width, Self.panelWidth, accuracy: 1)
        // The terminal, not the pane group: XCUITest clicks the group at its bottom edge here.
        app.element("smalti.terminal").click()
        app.run("<<<live >\"$SMALTI_UITEST_OUT\"")
        waitForOutput("live\n")
        XCTAssertTrue(panel.exists)
    }

    func testSliderMovesWithArrowsAndShift() {
        launchIsolated()
        openPanel()
        let opacity = control("opacity")
        opacity.click()
        let start = number(of: opacity)

        app.typeKey(.rightArrow, modifierFlags: [])
        expectValue(opacity, "\(start + 1)")
        app.typeKey(.leftArrow, modifierFlags: .shift)

        expectValue(opacity, "\(start + 1 - 10)")
    }

    func testAnsiEditOnlyAffectsCurrentTheme() {
        launchIsolated()
        openPanel()
        control("theme.bosque").click()
        control("ansi.1").click()
        expectThemeFile(contains: ["[appearance.ansi.bosque]", "1 = \"\(Self.pickedColor)\""])

        control("theme.obsidiana").click()

        expectValue(control("ansi.1"), "#f7768e")
        XCTAssertFalse(themeText().contains("[appearance.ansi.obsidiana]"))
    }

    /// C4: the panel's capture, kept in the runner's temporary `smalti-captures/` to lay over the board.
    func testPanelMatchesBoardCapture() throws {
        launchIsolated()
        openPanel()

        let captures = FileManager.default.temporaryDirectory.appending(path: "smalti-captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let window = app.windows.matching(identifier: "smalti.window").firstMatch
        try window.screenshot().pngRepresentation.write(to: captures.appending(path: "f5-apariencia.png"))

        XCTAssertEqual(panel.frame.height, window.frame.height, accuracy: 2)
        XCTAssertEqual(panel.frame.maxX, window.frame.maxX, accuracy: 2)
    }
}
