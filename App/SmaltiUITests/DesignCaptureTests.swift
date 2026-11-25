import AppKit
import XCTest

/// C18: window captures to lay over the boards (Reanudar.dc.html, Main.dc.html). They run only on demand:
/// `TEST_RUNNER_SMALTI_CAPTURE=1 scripts/test-ui.sh DesignCaptureTests`; PNGs land in the runner's temporary
/// directory, `smalti-captures/`.
final class DesignCaptureTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var captures: URL { FileManager.default.temporaryDirectory.appending(path: "smalti-captures") }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_CAPTURE"] == "1", "captures run on demand")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
    }

    func testCaptureResumeScreen() throws {
        let app = XCUIApplication.isolatedSmalti()
        // The runner lives in a container; the app abbreviates against the real home.
        let home = "/Users/\(NSUserName())"
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "\(home)/dev/solen", layout: "dwindle",
                    panes: [
                        .init(
                            directory: "\(home)/dev/solen", agentSessionID: "7f3a9c2e-1111-4b7a-9c11-2f6e5d4c3b2a",
                            title: "Agendar recordatorios al crear eventos", process: "claude"),
                        .init(directory: "\(home)/dev/solen", process: "zsh", lines: 1240, commands: 38),
                        .init(directory: "\(home)/dev/solen", relaunch: ["nvim", "+42"], process: "nvim"),
                    ]),
                .init(
                    name: "rizaria", root: "\(home)/dev/rizaria", layout: "columns",
                    panes: [
                        .init(
                            directory: "\(home)/dev/rizaria/web",
                            agentSessionID: "01980000-2222-4b7a-9c11-2f6e5d4c3b2a",
                            title: "Onboarding con preferencias de usuario", process: "claude"),
                        .init(directory: "\(home)/dev/rizaria", process: "zsh", lines: 320, commands: 12),
                    ]),
            ], alwaysRestore: false, in: app)
        self.app = app
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))

        try save(app.windows.firstMatch.screenshot(), as: "c18-restore.png")
    }

    /// F4 C11: the Tab menu at the cursor and the ⌃R palette, to lay over Main.dc.html and the approved mockups.
    func testCaptureInput() throws {
        let app = XCUIApplication.isolatedSmaltiWithIntegration()
        launch(app)
        Thread.sleep(forTimeInterval: 2)
        app.typeText("<<<one>\"$SMALTI_UITEST_OUT\"\n")
        app.typeText("<<<two>\"$SMALTI_UITEST_OUT\"\n")
        Thread.sleep(forTimeInterval: 1)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("git ch", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.completionMenu").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        try save(app.windows.firstMatch.screenshot(), as: "f4-completion-menu.png")
        try save(app.element("smalti.completionMenu").screenshot(), as: "f4-completion-menu-only.png")

        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("u", modifierFlags: .control)
        app.typeKey("r", modifierFlags: .control)
        XCTAssertTrue(app.element("smalti.historyPalette").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        try save(app.windows.firstMatch.screenshot(), as: "f4-history-palette.png")
        try save(app.element("smalti.historyPalette").screenshot(), as: "f4-history-palette-only.png")
    }

    /// F3 C12: the observatory over the bundled fixture, to lay over Observatorio.dc.html.
    func testCaptureObservatory() throws {
        let app = XCUIApplication.isolatedSmalti()
        try app.installObservatoryFixture(
            from: Bundle(for: Self.self), newestFirst: ["projects/-fixture-work-x/tools-session.jsonl"])
        launch(app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3)

        try save(app.windows.firstMatch.screenshot(), as: "f3-observatory.png")
    }

    /// F3 C12: the status bar's figures and a working Claude header with its model and "ctx N%".
    func testCaptureStatusAndHeader() throws {
        let app = XCUIApplication.isolatedSmalti()
        try app.installObservatoryFixture(from: Bundle(for: Self.self))
        launch(app)
        neutralPrompt(app)
        let session = "401a63e1-c076-45fe-9f09-432da1c8cfa6"
        app.run(#"printf '{"session_id":"\#(session)","source":"startup"}' | "$SMALTI_CLI" event SessionStart; clear"#)
        app.run(#"printf '{"session_id":"\#(session)","prompt":"x"}' | "$SMALTI_CLI" event UserPromptSubmit; clear"#)
        XCTAssertTrue(app.element("smalti.paneContext").waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)

        try save(app.windows.firstMatch.screenshot(), as: "f3-status-header.png")
    }

    /// F3 Task 0: the palette after arrowing to its last row (the selection used to sit below the clipped edge).
    func testCapturePaletteLastRowSelected() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        neutralPrompt(app)
        openPalette()
        let rows = app.elements("smalti.paletteRow").count
        for _ in 1..<rows { app.typeKey(.downArrow, modifierFlags: []) }

        try save(app.windows.firstMatch.screenshot(), as: "palette-last-row.png")
    }

    func testCaptureAgentStatus() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 3)
        app.typeKey("1", modifierFlags: .command)
        app.run(
            #"printf '{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","prompt":"x"}' | "$SMALTI_CLI" event UserPromptSubmit; clear"#
        )
        app.typeKey("2", modifierFlags: .command)
        app.run(#"printf '{"session_id":"9f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"}' | "$SMALTI_CLI" event Stop; clear"#)
        app.typeKey("1", modifierFlags: .command)
        let counter = app.element("smalti.counter.waiting")
        XCTAssertTrue(counter.waitForExistence(timeout: 5))

        try save(app.windows.firstMatch.screenshot(), as: "c18-status.png")
    }

    /// Committed captures show no host name, user or login banner: a bare prompt, and the workspace (named after the
    /// home folder) renamed to the board's "solen".
    private func neutralPrompt(_ app: XCUIApplication) {
        app.run("PS1='%# '; clear")
        openPalette()
        app.typeText("renombrar")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("solen")
        app.typeKey(.return, modifierFlags: [])
    }

    /// F4.5: "Retomar donde quedaste" grouped by window, then the two restored windows (mockup-windows.png). Only
    /// Smalti's windows are captured, never the whole screen.
    func testCaptureTwoWindows() throws {
        let app = XCUIApplication.isolatedSmalti()
        let mainHeight = NSScreen.screens.first?.frame.height ?? 900
        SessionState.seed(
            windows: [
                .init(
                    frame: (x: 40, y: mainHeight - 600, width: 760, height: 560),
                    workspaces: [
                        .init(name: "solen", root: "/tmp", layout: "dwindle", panes: [.init(directory: "/tmp")]),
                        .init(name: "billi", root: "/usr", layout: "dwindle", panes: [.init(directory: "/usr")]),
                    ]),
                .init(
                    frame: (x: 560, y: mainHeight - 820, width: 760, height: 560),
                    workspaces: [
                        .init(name: "smalti", root: "/tmp", layout: "columns", panes: [.init(directory: "/tmp")])
                    ]),
            ], frontIndex: 1, alwaysRestore: false, in: app)
        self.app = app
        app.launch()
        XCTAssertTrue(app.element("smalti.restore").waitForExistence(timeout: 10))
        try save(app.windows.firstMatch.screenshot(), as: "f45-resume-windows.png")

        app.typeKey(.return, modifierFlags: [])
        waitForShells(count: 2)
        let windows = app.windows.matching(identifier: "smalti.window").allElementsBoundByIndex
        for (index, window) in windows.enumerated() {
            // Committed captures show no host name or login banner (see `neutralPrompt`).
            window.click()
            app.run("PS1='%# '; clear")
            try save(window.screenshot(), as: "f45-window-\(index + 1).png")
        }
    }

    /// F4.5: the help over the window (mockup-help.png), with a neutral prompt behind it.
    func testCaptureHelp() throws {
        launch(.isolatedSmalti())
        neutralPrompt(app)
        app.typeKey("?", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.help").waitForExistence(timeout: 5))
        try save(app.windows.firstMatch.screenshot(), as: "f45-help.png")
    }

    /// F4.5: ⌘F over a pane with matches (mockup-search.png).
    func testCaptureSearch() throws {
        launch(.isolatedSmalti())
        neutralPrompt(app)
        app.run("printf 'warn  - Using edge runtime\\nok\\nwarn  - Unused export\\nok\\nwarn  - Image without alt\\n'")
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.search").waitForExistence(timeout: 5))
        app.typeText("warn")
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS ' de '"), object: app.element("smalti.searchCount"))
        wait(for: [counted], timeout: 5)
        try save(app.windows.firstMatch.screenshot(), as: "f45-search.png")
    }

    /// F4.5: "Reportar un problema o una idea" over the window (mockup-feedback.png).
    func testCaptureFeedback() throws {
        launch(.isolatedSmalti())
        neutralPrompt(app)
        openPalette()
        app.typeText("reportar")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.feedback").waitForExistence(timeout: 5))
        app.typeKey(.space, modifierFlags: [])
        try save(app.windows.firstMatch.screenshot(), as: "f45-feedback.png")
    }

    /// F4.5: each menu of the bar open, captured alone (mockup-menu.png).
    func testCaptureMenus() throws {
        launch(.isolatedSmalti())
        let bar = app.menuBars.firstMatch.children(matching: .menuBarItem).allElementsBoundByIndex.dropFirst()
        for (index, item) in bar.enumerated() {
            item.click()
            let menu = item.children(matching: .menu).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            try save(menu.screenshot(), as: "f45-menu-\(index + 1).png")
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    // MARK: - F5 (C4)

    private func smaltiWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.matching(identifier: "smalti.window").firstMatch
    }

    func testCaptureF5Themes() throws {
        for theme in ["obsidiana", "niebla", "ambar-nocturno", "bosque"] {
            let app = XCUIApplication.isolatedSmalti()
            app.writeTheme("[appearance]\ntheme = \"\(theme)\"\n")
            launch(app)
            app.typeKey("d", modifierFlags: .command)
            waitForShells(count: 2)
            app.run("ls /")
            sleep(1)
            try save(smaltiWindow(app).screenshot(), as: "f5-theme-\(theme).png")
            app.terminate()
        }
    }

    func testCaptureF5Appearance() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.appearance").waitForExistence(timeout: 5))
        sleep(1)
        try save(smaltiWindow(app).screenshot(), as: "f5-apariencia.png")
    }

    func testCaptureF5Studio() throws {
        let app = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
        launch(app)
        sleep(2)
        app.typeKey("p", modifierFlags: [.shift, .command])
        XCTAssertTrue(app.element("smalti.studio").waitForExistence(timeout: 5))
        sleep(1)
        try save(smaltiWindow(app).screenshot(), as: "f5-prompt.png")
    }

    // MARK: - F5.6 (C6, C11)

    /// The line colored while typing and the prompt with the new icons, in the four themes, over this repository
    /// (branch icon). The line is pasted without Return.
    func testCaptureF56Highlight() throws {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path(percentEncoded: false)
        for theme in ["obsidiana", "niebla", "ambar-nocturno", "bosque"] {
            let app = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
            app.writeTheme("[appearance]\ntheme = \"\(theme)\"\n")
            launch(app)
            sleep(2)
            app.run("cd '\(repository)'")
            sleep(2)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("git checkout -b \"feat x\" ~/src | grep -v foo > out.txt", forType: .string)
            app.typeKey("v", modifierFlags: .command)
            sleep(2)
            try save(smaltiWindow(app).screenshot(), as: "f56-highlight-\(theme).png")
            app.terminate()
        }
    }

    func testCaptureF56Studio() throws {
        let app = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
        launch(app)
        sleep(2)
        app.typeKey("p", modifierFlags: [.shift, .command])
        XCTAssertTrue(app.element("smalti.studio").waitForExistence(timeout: 5))
        sleep(1)
        try save(smaltiWindow(app).screenshot(), as: "f56-prompt-studio.png")
    }

    func testCaptureF5Buttons() throws {
        for mode in ["hidden", "hover", "visible"] {
            let app = XCUIApplication.isolatedSmalti(config: "[window]\nbuttons = \"\(mode)\"\n")
            launch(app)
            app.element(mode == "hover" ? "smalti.dragStrip" : "smalti.terminal").hover()
            sleep(1)
            try save(smaltiWindow(app).screenshot(), as: "f5-buttons-\(mode).png")
            app.terminate()
        }
    }

    func testCaptureF5SymbolOnly() throws {
        let app = XCUIApplication.isolatedSmaltiWithIntegration(smaltiPrompt: true)
        app.writeTheme("[prompt]\nstyle = \"symbol-only\"\n")
        launch(app)
        sleep(2)
        app.run("cd /tmp")
        sleep(1)
        try save(smaltiWindow(app).screenshot(), as: "f5-symbol-only.png")
    }

    /// The default theme with "Proteger legibilidad" over a white desktop (`mockup-legibility`).
    func testCaptureF5Legibility() throws {
        guard let screen = NSScreen.main else { return XCTFail("no main screen") }
        let white = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        white.backgroundColor = .white
        white.isReleasedWhenClosed = false
        white.orderFrontRegardless()
        defer { white.orderOut(nil) }
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        app.run("ls /")
        sleep(1)
        try save(smaltiWindow(app).screenshot(), as: "f5-legibility.png")
    }

    private func save(_ screenshot: XCUIScreenshot, as name: String) throws {
        try screenshot.pngRepresentation.write(to: captures.appending(path: name))
    }
}
