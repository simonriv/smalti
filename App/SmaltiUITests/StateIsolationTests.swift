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
}
