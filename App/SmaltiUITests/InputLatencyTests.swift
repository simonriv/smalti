import XCTest

/// F4 C13, on demand (`TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh InputLatencyTests`): 60 s of typing at the
/// prompt with ghost text, the Tab menu and git generators, over a 50,000-entry history, with the latency probe on.
/// No main-thread tick may be late by more than a frame (16 ms) while typing.
final class InputLatencyTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let typingSeconds: TimeInterval = 60
    private static let frameBudgetMs = 16.0
    private static let historyEntries = 50_000

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_MEASURE"] == "1", "measurements run on demand")
    }

    func testTypingNeverBlocksTheMainThread() throws {
        let app = XCUIApplication.isolatedSmaltiWithIntegration()
        let probe = FileManager.default.temporaryDirectory.appending(path: "input-latency-\(UUID().uuidString).json")
        app.launchArguments += ["-SmaltiLatencyProbe", probe.path(percentEncoded: false)]
        try seedHistory(in: app.stateDirectory)
        let launched = Date()
        launch(app)
        Thread.sleep(forTimeInterval: 3)

        // One round before the window, as F3 left opening the observatory out: the first accessibility snapshot
        // XCUITest takes of the app is the runner's cost, not typing's.
        if ProcessInfo.processInfo.environment["SMALTI_MEASURE_COLD"] != "1" { typeRound(0, in: app) }
        Thread.sleep(forTimeInterval: 1)
        let startedAtMs = Date().timeIntervalSince(launched) * 1_000
        let end = Date().addingTimeInterval(Self.typingSeconds)
        var round = 0
        // `SMALTI_MEASURE_IDLE=1` measures the same window without typing, as a baseline.
        let isIdle = ProcessInfo.processInfo.environment["SMALTI_MEASURE_IDLE"] == "1"
        if isIdle { Thread.sleep(forTimeInterval: Self.typingSeconds) }
        while !isIdle && Date() < end {
            typeRound(round, in: app)
            round += 1
        }
        let stoppedAtMs = Date().timeIntervalSince(launched) * 1_000
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: probe)) as? [String: Any] ?? [:]
        let late = (report["lateTicks"] as? [[Double]] ?? []).filter { $0[0] >= startedAtMs && $0[0] <= stoppedAtMs }
        print(
            "MEASURE rounds=\(round) ticks=\(report["ticks"] ?? 0) worst=\(report["worstDelayMs"] ?? 0) "
                + "window=\(Int(startedAtMs))…\(Int(stoppedAtMs)) ms whileTyping=\(late)")
        XCTAssertTrue(late.allSatisfy { $0[1] <= Self.frameBudgetMs }, "late ticks while typing: \(late)")
    }

    /// A prefix (ghost text), a pasted subcommand, Tab (menu and git generators), esc and ⌃U.
    private func typeRound(_ round: Int, in app: XCUIApplication) {
        app.typeText(["gi", "sw", "ma", "np", "do"][round % 5])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(" checkout ", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("u", modifierFlags: .control)
    }

    /// The JSON lines `FileCommandHistory` reads: 50,000 commands across 400 directories.
    private func seedHistory(in state: URL) throws {
        let folder = state.appending(path: "input")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pane = UUID().uuidString
        let now = Date().timeIntervalSinceReferenceDate
        var text = ""
        text.reserveCapacity(Self.historyEntries * 140)
        for index in 0..<Self.historyEntries {
            let command = ["git status", "git checkout main", "swift test", "make build", "npm run dev"][index % 5]
            text += "{\"command\":\"\(command) \(index % 3000)\",\"directory\":\"/bench/p\(index % 400)\","
                + "\"exit\":0,\"duration\":0.1,\"date\":\(now - Double(Self.historyEntries - index) * 60),"
                + "\"pane\":\"\(pane)\"}\n"
        }
        try Data(text.utf8).write(to: folder.appending(path: "history.jsonl"))
    }
}
