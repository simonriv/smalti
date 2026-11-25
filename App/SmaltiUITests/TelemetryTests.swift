import XCTest

/// F7: the local OTLP receiver. The telemetry comes from `scripts/otlp/fake-claude.py` running in a pane with
/// `zsh -f`, never from a real Claude; the Claude home and the managed settings are temporary.
final class TelemetryTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let toolsSession = "projects/-fixture-work-x/tools-session.jsonl"
    private static let emitter = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../scripts/otlp/fake-claude.py").standardized.path(percentEncoded: false)
    private static let variables = [
        "CLAUDE_CODE_ENABLE_TELEMETRY", "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "OTEL_EXPORTER_OTLP_LOGS_HEADERS",
        "OTEL_EXPORTER_OTLP_LOGS_PROTOCOL", "OTEL_LOGS_EXPORTER", "OTEL_LOGS_EXPORT_INTERVAL", "OTEL_METRICS_EXPORTER",
        "OTEL_TRACES_EXPORTER",
    ]

    private var probe: URL!  // Set per test in `launchTelemetry`.

    private func launchTelemetry(config: String? = nil, userSettings: String? = nil, fixture: Bool = false) throws {
        let app = XCUIApplication.isolatedSmalti()
        probe = app.configFile.deletingLastPathComponent().appending(path: "telemetry-probe.json")
        app.launchArguments += ["-SmaltiTelemetryProbe", probe.path(percentEncoded: false)]
        if let config { app.writeConfig(config) }
        if let userSettings {
            try FileManager.default.createDirectory(at: app.claudeHome, withIntermediateDirectories: true)
            try Data(userSettings.utf8).write(to: app.claudeHome.appending(path: "settings.json"))
        }
        if fixture { try app.installObservatoryFixture(from: Bundle(for: Self.self), newestFirst: [Self.toolsSession]) }
        launch(app)
    }

    private func probeStatus() -> [String: Any] {
        (try? Data(contentsOf: probe)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private func waitForProbe(_ status: String, timeout: TimeInterval = 10) {
        wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in self.probeStatus()["status"] as? String == status }, object: nil)
            ], timeout: timeout)
    }

    /// The telemetry variables a fresh pane sees, `NAME=value` sorted, with the token replaced by `<token>`.
    private func paneTelemetryVariables() -> [String] {
        app.run(
            #"env | grep -E '^(CLAUDE_CODE_ENABLE_TELEMETRY|OTEL_)' | sed -E 's/(Bearer )[0-9a-f]+/\1<token>/' | sort > "$SMALTI_UITEST_OUT.tmp" && mv "$SMALTI_UITEST_OUT.tmp" "$SMALTI_UITEST_OUT""#
        )
        let file = outputFile!
        wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: file.path) }, object: nil)
            ], timeout: 10)
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: file)
        return text.split(separator: "\n").map(String.init)
    }

    func testPaneReceivesTelemetryVariables() throws {
        try launchTelemetry()
        waitForProbe("listening")
        let port = try XCTUnwrap(probeStatus()["port"] as? Int)

        let variables = paneTelemetryVariables().sorted()

        XCTAssertEqual(
            variables,
            [
                "CLAUDE_CODE_ENABLE_TELEMETRY=1",
                "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://127.0.0.1:\(port)/v1/logs",
                "OTEL_EXPORTER_OTLP_LOGS_HEADERS=Authorization=Bearer <token>",
                "OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/json",
                "OTEL_LOGS_EXPORTER=otlp",
                "OTEL_LOGS_EXPORT_INTERVAL=5000",
                "OTEL_METRICS_EXPORTER=none",
                "OTEL_TRACES_EXPORTER=none",
            ].sorted())
    }

    func testFakeClaudeFeedsObservatoryDetail() throws {
        try launchTelemetry(fixture: true)
        waitForProbe("listening")

        app.run("/usr/bin/python3 '\(Self.emitter)' --session tools-session --requests 3 --errors 1 --interval 0")
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.observatory").waitForExistence(timeout: 5))

        let line = app.element("smalti.observatory.telemetry")
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (line.value as? String ?? "").contains("3 peticiones") }, object: nil)
        wait(for: [shown], timeout: 20)
        // The whole line but the clock: durations 1200, 1300 and 1400 ms (fake-claude.py) give a 1,3 s median.
        let text = line.value as? String ?? ""
        let clock = try XCTUnwrap(text.range(of: #"desde [0-9]{2}:[0-9]{2}"#, options: .regularExpression))
        XCTAssertEqual(
            text.replacingCharacters(in: clock, with: "desde HH:MM"),
            "Telemetría · desde HH:MM · 3 peticiones · mediana 1,3 s · 1 error de API · $0.04 según Claude Code")
        XCTAssertEqual(
            app.element("smalti.observatory.footnote").value as? String,
            "Datos: hooks, transcripts y telemetría de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."
        )
    }

    func testOtlpOffInjectsNothing() throws {
        try launchTelemetry(
            config: "[shell]\ncommand = \"\(XCUIApplication.isolatedShell)\"\n\n[extras]\notlp = false\n")
        waitForProbe("off")

        XCTAssertEqual(paneTelemetryVariables(), [])
    }

    func testUserConfiguredTelemetryIsRespected() throws {
        try launchTelemetry(userSettings: #"{"env":{"OTEL_EXPORTER_OTLP_ENDPOINT":"https://collector.example"}}"#)
        waitForProbe("configuredByUser")

        XCTAssertEqual(paneTelemetryVariables(), [])
        app.typeKey("a", modifierFlags: [.command, .shift])
        expect(
            app.element("smalti.observatory.footnote"),
            value: "Telemetría de Claude Code configurada fuera de Smalti: no se recibe aquí.")
    }

    func testReloadTurnsReceiverOff() throws {
        try launchTelemetry()
        waitForProbe("listening")

        app.writeConfig("[shell]\ncommand = \"\(XCUIApplication.isolatedShell)\"\n\n[extras]\notlp = false\n")
        reloadConfigFromPalette()
        waitForProbe("off")
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)

        XCTAssertEqual(paneTelemetryVariables(), [])
    }

    func testReloadTurnsReceiverOn() throws {
        try launchTelemetry(
            config: "[shell]\ncommand = \"\(XCUIApplication.isolatedShell)\"\n\n[extras]\notlp = false\n")
        waitForProbe("off")

        app.writeConfig("[shell]\ncommand = \"\(XCUIApplication.isolatedShell)\"\n")
        reloadConfigFromPalette()
        waitForProbe("listening")
        app.typeKey("d", modifierFlags: .command)
        waitForShells(count: 2)

        XCTAssertEqual(paneTelemetryVariables().count, 8)
    }
}
