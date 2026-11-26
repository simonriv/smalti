import XCTest

/// F8.5: projects. Each test builds its own repo in a temporary folder (an empty `.git/` and `.smalti/layout.json`)
/// whose first pane runs `touch <witness>`: the witness file says whether a command of the repo ran.
final class ProjectTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    /// The repo (real path: the temporary folder sits under a link) and the witness its command touches.
    private var repo: URL!  // Created per test in setUp.
    private var witness: URL!  // Same.

    override func setUp() async throws {
        try await super.setUp()
        let base = FileManager.default.temporaryDirectory.appending(path: "smalti-projects-\(UUID().uuidString)")
        repo = base.appending(path: "rizaria").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appending(path: "web"), withIntermediateDirectories: true)
        witness = base.appending(path: "witness").resolvingSymlinksInPath()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: repo.deletingLastPathComponent())
    }

    private var root: String { repo.path(percentEncoded: false).trimmingTrailingSlash }

    /// `.smalti/layout.json` with one pane per command (`nil` is a shell).
    private func writeProject(_ commands: [[String]?]) throws {
        let panes = commands.map { command -> String in
            guard let command else { return #"{"directory":"."}"# }
            let quoted = command.map { "\"\($0)\"" }.joined(separator: ",")
            return #"{"directory":".","command":[\#(quoted)]}"#
        }
        let tree = (1..<max(commands.count, 1)).reduce(#"{"leaf":{"index":0}}"#) { tree, index in
            #"{"split":{"axis":"sideBySide","ratio":0.5,"first":\#(tree),"second":{"leaf":{"index":\#(index)}}}}"#
        }
        let json = """
            {"smaltiLayout":1,"name":"rizaria","root":".","layout":"dwindle","focused":0,"tree":\(tree),
            "panes":[\(panes.joined(separator: ","))]}
            """
        try FileManager.default.createDirectory(at: repo.appending(path: ".smalti"), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: repo.appending(path: ".smalti/layout.json"))
    }

    private var witnessCommand: [String] { ["touch", witness.path(percentEncoded: false)] }

    /// Makes the repo (and `others`, newer first after it) recent projects of the isolated app, never approved.
    private func seedRecent(in app: XCUIApplication, others: [(root: String, name: String)] = []) throws {
        let records: [[String: Any]] =
            [["root": root, "name": "rizaria", "lastOpened": "2026-11-25T10:00:00Z"]]
            + others.map { ["root": $0.root, "name": $0.name, "lastOpened": "2026-11-24T10:00:00Z"] }
        let state = app.stateDirectory
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "projects": records])
            .write(to: state.appending(path: "projects.json"))
    }

    /// A second repo next to the first, with only a shell.
    private func secondProject(_ name: String) throws -> String {
        let other = repo.deletingLastPathComponent().appending(path: name)
        try FileManager.default.createDirectory(at: other.appending(path: ".smalti"), withIntermediateDirectories: true)
        let json = #"{"smaltiLayout":1,"name":"\#(name)","root":".","layout":"dwindle","panes":[{"directory":"."}]}"#
        try Data(json.utf8).write(to: other.appending(path: ".smalti/layout.json"))
        return other.path(percentEncoded: false).trimmingTrailingSlash
    }

    private func selectedRow() -> String? {
        app.elements("smalti.projects.row").allElementsBoundByIndex.first { ($0.value as? String) == "selected" }?
            .label
    }

    private func launchWithRecent() throws {
        let app = XCUIApplication.isolatedSmalti()
        try seedRecent(in: app)
        launch(app)
    }

    /// ⌘O, then ↩ on the preselected project.
    private func openRecent() {
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.projects").waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.projects").waitForNonExistence(timeout: 5))
    }

    private var card: XCUIElement { app.element("smalti.projects.confirm") }

    private func waitForWitness(timeout: TimeInterval = 10) -> Bool {
        let exists = XCTNSPredicateExpectation(
            predicate: NSPredicate { [witness] _, _ in
                FileManager.default.fileExists(atPath: witness?.path(percentEncoded: false) ?? "")
            }, object: nil)
        return XCTWaiter().wait(for: [exists], timeout: timeout) == .completed
    }

    private func workspaceNames() -> [String] {
        app.elements("smalti.workspace").allElementsBoundByIndex.map(\.label)
    }

    private func runFromPalette(_ query: String) {
        openPalette()
        app.typeText(query)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    // MARK: C1, C2

    func testConfirmOpensLayoutAndRuns() throws {
        try writeProject([witnessCommand, nil])
        try launchWithRecent()

        openRecent()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.projects.command").count, 1)
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        // The message is transient (4 s): read it before waiting for the command.
        expect(app.element("smalti.statusBar"), value: "Proyecto “rizaria” abierto")
        XCTAssertTrue(waitForWitness(), "the approved command ran")
        waitForPaneCount(2)
        XCTAssertEqual(workspaceNames().count, 2)
    }

    func testCancelRunsNothing() throws {
        try writeProject([witnessCommand, nil])
        try launchWithRecent()

        openRecent()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertFalse(waitForWitness(timeout: 3), "nothing of the repo runs without approval")
        XCTAssertEqual(workspaceNames().count, 1)
        waitForPaneCount(1)
    }

    // MARK: C3, C4

    func testUnchangedOpensWithoutConfirmationAndChangedAsks() throws {
        try writeProject([witnessCommand])
        try launchWithRecent()
        openRecent()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForWitness())
        runFromPalette("cerrarworkspace")
        XCTAssertEqual(workspaceNames().count, 1)
        try FileManager.default.removeItem(at: witness)

        openRecent()

        XCTAssertFalse(card.waitForExistence(timeout: 2), "an approved, unchanged file opens without asking")
        XCTAssertTrue(waitForWitness())
        runFromPalette("cerrarworkspace")
        try writeProject([witnessCommand, ["true"]])

        openRecent()

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let values = app.elements("smalti.projects.command").allElementsBoundByIndex.compactMap { $0.value as? String }
        XCTAssertEqual(values, ["same", "added"])
        app.typeKey(.escape, modifierFlags: [])
    }

    func testOpenTwiceJumps() throws {
        try writeProject([witnessCommand])
        try launchWithRecent()
        openRecent()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForWitness())
        app.typeKey("1", modifierFlags: .control)
        try FileManager.default.removeItem(at: witness)

        openRecent()

        XCTAssertFalse(card.waitForExistence(timeout: 2))
        XCTAssertEqual(workspaceNames().count, 2, "jumping does not open the project again")
        XCTAssertEqual(app.elements("smalti.workspace").element(boundBy: 1).value as? String, "active")
        XCTAssertFalse(waitForWitness(timeout: 2), "jumping runs nothing")
    }

    // MARK: The selector (review 2)

    func testCommandOMovesToTheNextAndTypingFilters() throws {
        try writeProject([nil])
        let app = XCUIApplication.isolatedSmalti()
        try seedRecent(in: app, others: [(try secondProject("acme"), "acme")])
        launch(app)

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.projects").waitForExistence(timeout: 5))
        XCTAssertEqual(selectedRow(), "rizaria")
        app.typeKey("o", modifierFlags: .command)
        XCTAssertEqual(selectedRow(), "acme", "⌘O inside the selector moves to the next project")

        app.typeText("acm")
        XCTAssertEqual(app.elements("smalti.projects.row").count, 1)
        app.typeText("zzz")
        XCTAssertTrue(app.element("smalti.projects.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(app.element("smalti.projects.empty").value as? String, "Ningún proyecto coincide con «acmzzz»")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testClickingARowOpensIt() throws {
        try writeProject([nil])
        try launchWithRecent()
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.projects").waitForExistence(timeout: 5))

        app.elements("smalti.projects.row").firstMatch.click()

        XCTAssertTrue(app.element("smalti.projects").waitForNonExistence(timeout: 5))
        XCTAssertEqual(workspaceNames().count, 2)
    }

    func testJumpsToTheProjectInAnotherWindow() throws {
        try writeProject([nil])
        try launchWithRecent()
        openRecent()
        XCTAssertEqual(workspaceNames().count, 2)
        app.typeKey("n", modifierFlags: .command)
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.windows)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: 10), .completed)

        openRecent()

        XCTAssertEqual(app.windows.count, 2, "jumping opens no window")
        let front = app.windows.element(boundBy: 0)
        let chip = front.descendants(matching: .any).matching(identifier: "smalti.workspace")
            .matching(NSPredicate(format: "label == %@", "rizaria")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the project's window comes to the front")
        XCTAssertEqual(chip.value as? String, "active")
    }

    // MARK: C5

    func testRecentsSurviveRelaunchAndDropMissing() throws {
        try writeProject([nil])
        try launchWithRecent()
        openRecent()
        waitForPaneCount(1)
        XCTAssertEqual(workspaceNames().count, 2, "a layout with only shells opens without asking")
        app.terminate()
        try? FileManager.default.removeItem(at: app.stateDirectory.appending(path: "session.json"))
        launch(.relaunched(from: app))

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.element("smalti.projects").waitForExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.projects.row").firstMatch.label, "rizaria")
        app.typeKey(.escape, modifierFlags: [])
        try FileManager.default.removeItem(at: repo.appending(path: ".smalti/layout.json"))

        app.typeKey("o", modifierFlags: .command)

        XCTAssertTrue(app.element("smalti.projects.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(app.elements("smalti.projects.row").count, 0)
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: C6, C7 (the pane's folder comes from the shell integration, OSC 7)

    /// `cd` in the pane and waits until its header shows the folder (OSC 7 reached the app): saving before that
    /// would write in the pane's first folder.
    private func launchInRepo(_ folder: String, endingWith last: String) {
        launch(.isolatedSmaltiWithIntegration())
        app.run("cd \(folder)")
        let header = app.element("smalti.paneHeader")
        let arrived = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (header.value as? String)?.hasSuffix(last) == true }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [arrived], timeout: 10), .completed, "the pane is in \(folder)")
    }

    func testOffersProjectInPalette() throws {
        try writeProject([nil])
        launchInRepo(repo.appending(path: "web").path(percentEncoded: false), endingWith: "web")

        openPalette()
        app.typeText("proyecto")

        XCTAssertTrue(
            app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == %@", "Abrir proyecto “rizaria”"))
                .firstMatch.waitForExistence(timeout: 5))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "· en este panel")).firstMatch
        XCTAssertTrue(subtitle.exists, "C7: the row says it is the focused pane's project")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Review 2: ⌘K reads the projects once when it opens, not on every key typed.
    func testThePaletteReadsProjectsOncePerOpening() throws {
        launchInRepo(root, endingWith: "rizaria")
        openPalette()
        try writeProject([nil])
        app.typeText("proyecto")
        let row = app.elements("smalti.paletteRow").matching(
            NSPredicate(format: "label == %@", "Abrir proyecto “rizaria”")
        ).firstMatch
        XCTAssertFalse(row.waitForExistence(timeout: 2), "typing does not search the disk again")
        app.typeKey(.escape, modifierFlags: [])

        openPalette()
        app.typeText("proyecto")

        XCTAssertTrue(row.waitForExistence(timeout: 5), "the next opening finds it")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testSaveWritesAndAsksBeforeReplacing() throws {
        launchInRepo(root, endingWith: "rizaria")
        let file = repo.appending(path: ".smalti/layout.json")

        runFromPalette("guardarlayoutdelproyecto")

        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 5), .completed)
        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.contains("\"root\" : \".\""))
        XCTAssertFalse(written.contains(NSHomeDirectory()))

        runFromPalette("guardarlayoutdelproyecto")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), written)
    }
}

extension String {
    fileprivate var trimmingTrailingSlash: String { count > 1 && hasSuffix("/") ? String(dropLast()) : self }
}
