import XCTest

/// F6 C7, on demand (`TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh SessionSearchLatencyTests`): the ⌘⇧O card opens
/// with every store read in 100 ms or less. The stores are the fixtures: Codex, Antigravity and OpenCode seeded as in
/// `SessionSearchTests`, and Claude's recorded transcripts. The app writes each open's time
/// (`-SmaltiSessionSearchTimings`); the test prints p50 and p95 and checks p95.
final class SessionSearchLatencyTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let samples = 12
    private static let claudeFixture = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(
            path: "../../Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/claude/home/.claude")
    private var timingsFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_MEASURE"] == "1", "measurements run on demand")
        timingsFile = FileManager.default.temporaryDirectory.appending(path: "smalti-sessions-\(UUID().uuidString).txt")
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: timingsFile)
    }

    func testCardOpensWithin100Ms() throws {
        let smalti = XCUIApplication.isolatedSmalti()
        smalti.launchArguments += ["-SmaltiSessionSearchTimings", timingsFile.path(percentEncoded: false)]
        smalti.seedHarnessStoresFromRunner()
        let claudeHome = URL(filePath: smalti.launchArgument("-SmaltiClaudeHome"))
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.claudeFixture.appending(path: "projects"), to: claudeHome.appending(path: "projects"))
        launch(smalti)
        let card = app.element("sessions.search")

        for _ in 0..<Self.samples {
            app.typeKey("o", modifierFlags: [.command, .shift])
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            sleep(1)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        }

        let times = try String(contentsOf: timingsFile, encoding: .utf8).split(separator: "\n").compactMap {
            Double($0)
        }.sorted()
        XCTAssertGreaterThanOrEqual(times.count, Self.samples)
        let p50 = times[times.count / 2]
        let p95 = times[Int((Double(times.count) * 0.95).rounded(.up)) - 1]
        print("SESSION-SEARCH-LATENCY p50 \(p50) ms p95 \(p95) ms over \(times.count) opens")
        XCTAssertLessThanOrEqual(p95, 100)
    }
}
