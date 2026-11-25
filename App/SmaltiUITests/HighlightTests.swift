import XCTest

/// F5.6 (spec C6, C7): the line typed at the prompt is colored by zsh with Smalti's spans and the theme's colors.
/// The test `.zshrc` binds ⌃X⌃D to a widget that writes `region_highlight` to `$SMALTI_UITEST_OUT`, so the test
/// reads what zsh paints without any test-only switch in the app. Spaces cannot be typed (⌃Space on this layout).
final class HighlightTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let dumpWidget = """
        PS1='p%% '
        _t() { print -r -- "${region_highlight[*]}" >| "$SMALTI_UITEST_OUT" }
        zle -N _t
        bindkey '^X^D' _t
        """

    private func launchWithDump() {
        let smalti = XCUIApplication.isolatedSmaltiWithIntegration()
        let zshrc = smalti.configFile.deletingLastPathComponent().appending(path: "zdotdir/.zshrc")
        try? Self.dumpWidget.write(to: zshrc, atomically: true, encoding: .utf8)
        launch(smalti)
        sleep(2)  // zsh's first prompt installs the input script.
    }

    /// What zsh paints now (`region_highlight`), Smalti's entries only.
    private func highlight() -> [String] {
        try? FileManager.default.removeItem(at: outputFile)
        app.typeKey("x", modifierFlags: .control)
        app.typeKey("d", modifierFlags: .control)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let text = try? String(contentsOf: outputFile, encoding: .utf8), text.hasSuffix("\n") {
                return text.matches(of: /\d+ \d+ [^ ]+ memo=smaltihl/).map { String($0.output) }
            }
            usleep(100_000)
        }
        return []
    }

    private func waitForHighlight(_ expected: (([String]) -> Bool)) -> [String] {
        var last: [String] = []
        for _ in 0..<10 {
            last = highlight()
            if expected(last) { return last }
            sleep(1)
        }
        return last
    }

    func testTypedCommandIsColored() {
        launchWithDump()

        app.typeText("ls|wc")

        let spans = waitForHighlight { $0.count == 3 }
        XCTAssertEqual(spans.map { $0.split(separator: " ").prefix(2).joined(separator: " ") }, ["0 2", "2 3", "3 5"])
        XCTAssertTrue(spans[0].hasPrefix("0 2 fg=#"), "\(spans)")
    }

    func testThemeChangeRepaintsOpenLine() {
        launchWithDump()
        app.typeText("ls")
        let before = waitForHighlight { !$0.isEmpty }
        XCTAssertFalse(before.isEmpty)

        app.writeTheme("[prompt]\nsource = \"shell\"\n\n[appearance]\ntheme = \"niebla\"\n")
        reloadConfigFromPalette()

        let after = waitForHighlight { !$0.isEmpty && $0 != before }
        XCTAssertNotEqual(after, before)
        XCTAssertFalse(after.isEmpty)
    }

    func testHighlightingOffClearsWithoutRelaunch() {
        launchWithDump()
        app.typeText("ls")
        XCTAssertFalse(waitForHighlight { !$0.isEmpty }.isEmpty)

        app.writeConfig("[input]\nhighlighting = false\n")
        reloadConfigFromPalette()

        XCTAssertTrue(waitForHighlight { $0.isEmpty }.isEmpty)
    }
}
