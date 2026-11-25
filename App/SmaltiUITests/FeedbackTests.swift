import XCTest

/// F4.5 C11: "Reportar un problema o una idea" opens a prefilled GitHub issue with the version and commit; the logs
/// are saved (to a temporary Downloads in tests) only when the box is checked; "Mostrar registros…" saves them alone.
final class FeedbackTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var openLog: URL { outputFile.appendingPathExtension("opened") }
    private var downloads: URL { outputFile.appendingPathExtension("downloads") }

    private func launchWithLogs() {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += [
            "-SmaltiOpenLog", openLog.path(percentEncoded: false), "-SmaltiDownloadsPath",
            downloads.path(percentEncoded: false),
        ]
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        launch(app)
    }

    private func opened() -> [String] {
        ((try? String(contentsOf: openLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    private func waitForOpened(_ count: Int) {
        let done = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in opened().count >= count }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 10), .completed, "opened: \(opened())")
    }

    private func savedLogs() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: downloads.path(percentEncoded: false)))?
            .filter { $0.hasPrefix("smalti-registros-") } ?? []
    }

    private func openFeedback() {
        openPalette()
        app.typeText("reportar")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.feedback").waitForExistence(timeout: 5))
    }

    func testFeedbackOpensTheIssueWithTheVersion() throws {
        launchWithLogs()
        openFeedback()

        app.typeKey(.return, modifierFlags: [])

        waitForOpened(1)
        let url = try XCTUnwrap(URLComponents(string: opened().last ?? ""))
        XCTAssertEqual(url.path, "/simonriv/smalti/issues/new")
        // F7.6: the public repo's issue form, with the build in its own field.
        let build = url.queryItems?.first { $0.name == "build" }?.value ?? ""
        XCTAssertNotNil(build.range(of: #"^Smalti [0-9]+\.[0-9]+\.[0-9]+ \("#, options: .regularExpression), build)
        XCTAssertEqual(url.queryItems?.first { $0.name == "template" }?.value, "bug.yml")
        XCTAssertTrue(savedLogs().isEmpty)
    }

    func testIdeaWithLogsSavesThemFirst() throws {
        launchWithLogs()
        openFeedback()

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        waitForOpened(2)
        XCTAssertEqual(savedLogs().count, 1)
        XCTAssertTrue(opened().contains { $0.hasPrefix(downloads.path(percentEncoded: false)) })
        let url = try XCTUnwrap(URLComponents(string: opened().last ?? ""))
        XCTAssertEqual(url.queryItems?.first { $0.name == "template" }?.value, "idea.yml")
    }

    func testEscapeCancels() {
        launchWithLogs()
        openFeedback()

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(app.element("smalti.feedback").waitForNonExistence(timeout: 5))
        XCTAssertTrue(opened().isEmpty)
    }

    func testShowLogsWritesTheFile() throws {
        launchWithLogs()

        app.menuBars.menuBarItems["Ayuda"].click()
        app.menuBars.menuItems["Mostrar registros…"].click()

        waitForOpened(1)
        let file = try XCTUnwrap(savedLogs().first)
        let text = try String(contentsOf: downloads.appending(path: file), encoding: .utf8)
        // F7.6: any version (it named 0.5.6 and broke with every release since).
        XCTAssertNotNil(
            text.range(of: #"^Smalti [0-9]+\.[0-9]+\.[0-9]+ \("#, options: .regularExpression), String(text.prefix(80)))
    }
}
