import XCTest

/// F7.6 C5: "Buscar actualizaciones…" asks Sparkle, whose window speaks Spanish; the automatic check toggles from ⌘K;
/// Smalti Dev without a feed offers neither. The feed is a local server with an older version, so nothing downloads.
final class UpdatesTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private let port = Int.random(in: 20_000...29_999)

    private var feed: URL { URL(string: "http://127.0.0.1:\(port)/appcast.xml")! }  // A constant, valid URL.

    /// An appcast whose only item is older than any real build, served on 127.0.0.1 by Python inside a Smalti pane:
    /// the test runner's sandbox cannot listen on a port. The server exits on its own after two minutes and with
    /// the pane's shell, so nothing outlives the test.
    private func serveOlderAppcast() throws {
        let folder = outputFile.appendingPathExtension("feed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let appcast = """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel><title>Smalti</title>
                <item><title>0.0.1</title><sparkle:version>1</sparkle:version>
                  <sparkle:shortVersionString>0.0.1</sparkle:shortVersionString>
                  <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
                  <enclosure url="http://127.0.0.1:\(port)/Smalti.dmg" length="1" type="application/octet-stream"
                    sparkle:edSignature="AAAA" /></item>
              </channel>
            </rss>
            """
        try Data(appcast.utf8).write(to: folder.appending(path: "appcast.xml"))
        let ready = folder.appending(path: "ready")
        let script = folder.appending(path: "serve.py")
        try Data(
            """
            import functools, http.server, os, pathlib, sys, threading
            threading.Timer(120, lambda: os._exit(0)).start()
            handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[2])
            server = http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), handler)
            pathlib.Path(sys.argv[3]).write_text("ok")
            server.serve_forever()
            """.utf8
        ).write(to: script)
        let path = { (url: URL) in url.path(percentEncoded: false) }
        app.run("/usr/bin/python3 '\(path(script))' \(port) '\(path(folder))' '\(path(ready))' 2>/dev/null &")
        let listening = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path(ready)) }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [listening], timeout: 15), .completed, "the feed server did not start")
    }

    private func launch(feed: URL?) {
        let app = XCUIApplication.isolatedSmalti()
        if let feed { app.launchArguments += ["-SmaltiUpdateFeedURL", feed.absoluteString] }
        launch(app)
    }

    private func run(_ query: String) {
        openPalette()
        app.typeText(query)
        app.typeKey(.return, modifierFlags: [])
    }

    func testCheckForUpdatesShowsSparkleInSpanish() throws {
        launch(feed: feed)
        try serveOlderAppcast()

        run("buscar actualizaciones")

        let upToDate = app.staticTexts["¡Estás al día!"]
        XCTAssertTrue(upToDate.waitForExistence(timeout: 15), "Sparkle did not say the build is the newest")
        app.typeKey(.return, modifierFlags: [])
    }

    /// The toggle is remembered in Smalti Dev's defaults, so the test starts from whichever state it finds, flips it
    /// twice and leaves it as it was.
    func testAutomaticChecksToggleFromThePalette() throws {
        launch(feed: feed)
        let turnOff = "Desactivar actualizaciones automáticas"
        let turnOn = "Activar actualizaciones automáticas"
        let first = toggleTitle()
        XCTAssertTrue([turnOff, turnOn].contains(first), "no automatic-updates row: \(first)")

        app.typeKey(.return, modifierFlags: [])
        expectStatus(
            first == turnOff ? "Actualizaciones automáticas desactivadas" : "Actualizaciones automáticas activadas")
        let second = toggleTitle()
        XCTAssertEqual(second, first == turnOff ? turnOn : turnOff)
        app.typeKey(.return, modifierFlags: [])
        expectStatus(
            first == turnOff ? "Actualizaciones automáticas activadas" : "Actualizaciones automáticas desactivadas")
    }

    /// Opens ⌘K on the toggle and returns its title, leaving the palette open on it.
    private func toggleTitle() -> String {
        openPalette()
        app.typeText("actualizaciones automáticas")
        let row = app.elements("smalti.paletteRow").matching(
            NSPredicate(format: "label ENDSWITH 'actualizaciones automáticas'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        return row.label
    }

    private func expectStatus(_ text: String) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", text), object: app.element("smalti.statusBar"))
        wait(for: [shown], timeout: 5)
    }

    /// Review 2 (M9): the same check from the Smalti menu, under "Acerca de Smalti".
    func testCheckForUpdatesFromTheSmaltiMenu() throws {
        launch(feed: feed)
        try serveOlderAppcast()

        appMenu().click()
        app.menuBars.menuItems["Buscar actualizaciones…"].click()

        XCTAssertTrue(app.staticTexts["¡Estás al día!"].waitForExistence(timeout: 15))
        app.typeKey(.return, modifierFlags: [])
    }

    func testSmaltiDevWithoutAFeedHasNoUpdateMenuItems() {
        launch(feed: nil)

        appMenu().click()

        XCTAssertTrue(app.menuBars.menuItems["Acerca de Smalti"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuBars.menuItems["Buscar actualizaciones…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// The app's own menu, right of the Apple menu.
    private func appMenu() -> XCUIElement {
        app.menuBars.firstMatch.children(matching: .menuBarItem).element(boundBy: 1)
    }

    func testSmaltiDevWithoutAFeedOffersNoUpdates() {
        launch(feed: nil)

        openPalette()
        app.typeText("buscar actualizaciones")

        XCTAssertFalse(
            app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == 'Buscar actualizaciones…'"))
                .firstMatch.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// F7.7: documentation, support and privacy open in the interface's language.
    private func openedLinks(language: String, commands: [String]) throws -> [String] {
        let openLog = outputFile.appendingPathExtension("opened-\(language)")
        let app = XCUIApplication.isolatedSmalti(language: language)
        app.launchArguments += ["-SmaltiOpenLog", openLog.path(percentEncoded: false)]
        launch(app)
        commands.forEach(run)
        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                ((try? String(contentsOf: openLog, encoding: .utf8)) ?? "").split(separator: "\n").count
                    >= commands.count
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 10), .completed)
        return try String(contentsOf: openLog, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func testDocumentationSupportAndPrivacyOpenTheSpanishWeb() throws {
        let lines = try openedLinks(
            language: "es", commands: ["abrir la documentación", "apoyar smalti", "política de privacidad"])

        XCTAssertEqual(
            lines, ["https://smalti.sh/es/docs", "https://smalti.sh/es#apoyar", "https://smalti.sh/es/privacy"])
    }

    func testDocumentationSupportAndPrivacyOpenTheEnglishWeb() throws {
        let lines = try openedLinks(
            language: "en", commands: ["open the documentation", "support smalti", "privacy policy"])

        XCTAssertEqual(lines, ["https://smalti.sh/docs", "https://smalti.sh/#support", "https://smalti.sh/privacy"])
    }
}
