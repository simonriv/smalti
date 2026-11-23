import XCTest

/// C11, on demand (`TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh ObservatoryLatencyTests`): the observatory
/// stays open on "30 días" for 60 s over a heavy synthetic history (300 sessions, 60 turns each, spread over 30
/// days) with the latency probe on. Prints the late main-thread ticks that happened while it was open.
final class ObservatoryLatencyTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let sessions = 300
    private static let turnsPerSession = 60
    private static let openSeconds: TimeInterval = 60
    private static let frameBudgetMs = 16.0
    private static let settleSeconds: TimeInterval = 3

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_MEASURE"] == "1", "measurements run on demand")
    }

    func testRefreshNeverBlocksTheMainThreadWithTheObservatoryOpen() throws {
        let app = XCUIApplication.isolatedSmalti()
        let probe = FileManager.default.temporaryDirectory.appending(
            path: "observatory-latency-\(UUID().uuidString).json")
        app.launchArguments += ["-SmaltiLatencyProbe", probe.path(percentEncoded: false)]
        try writeHeavyHistory(into: app.claudeHome)
        let launched = Date()
        launch(app)
        // `SMALTI_MEASURE_CLOSED=1` measures the same run with the observatory closed, as a baseline.
        if ProcessInfo.processInfo.environment["SMALTI_MEASURE_CLOSED"] != "1" {
            app.typeKey("a", modifierFlags: [.command, .shift])
            XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 10))
            app.typeKey("p", modifierFlags: .command)
            app.typeKey("p", modifierFlags: .command)
        }
        // C11 is about refreshes: opening and switching period are the user's own actions, left out of the window.
        Thread.sleep(forTimeInterval: Self.settleSeconds)
        let openedAtMs = Date().timeIntervalSince(launched) * 1_000
        Thread.sleep(forTimeInterval: Self.openSeconds)
        let closedAtMs = Date().timeIntervalSince(launched) * 1_000
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: probe)) as? [String: Any] ?? [:]
        let late = (report["lateTicks"] as? [[Double]] ?? []).filter { $0[0] >= openedAtMs && $0[0] <= closedAtMs }
        print(
            "MEASURE ticks=\(report["ticks"] ?? 0) worst=\(report["worstDelayMs"] ?? 0) window=\(Int(openedAtMs))…"
                + "\(Int(closedAtMs)) ms whileOpen=\(late) all=\(report["lateTicks"] ?? [])")
        XCTAssertTrue(late.allSatisfy { $0[1] <= Self.frameBudgetMs }, "late ticks while open: \(late)")
    }

    /// 300 transcripts × 60 replies with tools, one per day across the last 30 days.
    private func writeHeavyHistory(into home: URL) throws {
        let formatter = ISO8601DateFormatter()
        for session in 0..<Self.sessions {
            let project = home.appending(path: "projects/-bench-p\(session % 12)")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let start = Date().addingTimeInterval(-Double(session % 30) * 86_400 - 3_600)
            let lines = (0..<Self.turnsPerSession).flatMap { turn -> [String] in
                let at = formatter.string(from: start.addingTimeInterval(Double(turn) * 30))
                let id = "s\(session)-t\(turn)"
                return [
                    #"{"type":"assistant","timestamp":"\#(at)","sessionId":"bench-\#(session)","cwd":"/bench/p\#(session % 12)","message":{"id":"\#(id)","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"u\#(id)","name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":3,"output_tokens":\#(turn * 7),"cache_read_input_tokens":40000,"cache_creation_input_tokens":200}}}"#,
                    #"{"type":"user","timestamp":"\#(at)","sessionId":"bench-\#(session)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u\#(id)","content":"ok"}]}}"#,
                ]
            }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(
                to: project.appending(path: "bench-\(session).jsonl"))
        }
    }
}
