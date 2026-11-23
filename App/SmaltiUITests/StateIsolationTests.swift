import XCTest

/// F2 part A (issue #6): a development build launched by the tests keeps everything it writes in its own,
/// owner-only state directory, never in the daily Smalti's.
final class StateIsolationTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    func testEngineConfigLivesInTheIsolatedStateDirectory() {
        let app = XCUIApplication.isolatedSmalti()

        launch(app)

        let file = app.stateDirectory.appending(path: "ghostty.conf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    func testExistingStateDirectoryBecomesOwnerOnly() throws {
        let app = XCUIApplication.isolatedSmalti()
        try FileManager.default.createDirectory(
            at: app.stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

        launch(app)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: app.stateDirectory.path(percentEncoded: false))
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
    }

    /// A session that cannot be saved is reported once in the status bar, not only in the log.
    func testFailedSaveIsShownInTheStatusBar() throws {
        let app = XCUIApplication.isolatedSmalti()
        let blocker = app.stateDirectory.appending(path: "session.json")
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appending(path: "blocks-the-file"))
        // Read-only, so the save can neither replace it nor empty it.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: blocker.path(percentEncoded: false))
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: blocker.path(percentEncoded: false))
        }
        launch(app)

        app.typeKey("d", modifierFlags: .command)

        let reported = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "No se pudo guardar la sesión"),
            object: app.element("smalti.statusBar"))
        wait(for: [reported], timeout: 6)
    }
}
