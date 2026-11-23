import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C14: the plugin Smalti ships is valid, its hooks do nothing outside Smalti, and install/uninstall run the
/// expected `claude plugin` commands (against a fake `claude` that records them).
@MainActor
@Suite("Claude plugin installer", .serialized)
struct ClaudePluginInstallerTests {
    nonisolated private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    nonisolated private static let pluginSource = repository.appending(path: "App/ClaudePlugin")
    nonisolated private static let realClaude = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: ".local/bin/claude")

    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-plugin-\(UUID())")
    private var log: URL { work.appending(path: "claude.log") }
    private var installDirectory: URL { work.appending(path: "installed/claude-plugin") }

    init() throws {
        let bin = work.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
            #!/bin/sh
            echo "$*" >> "$LOG"
            [ -n "$FAIL_ON" ] && [ "$*" = "$FAIL_ON" ] && { echo boom; echo detalle; exit 1; }
            case "$*" in
              "plugin install smalti@smalti") touch "$STATE" ;;
              "plugin uninstall smalti@smalti") rm -f "$STATE" ;;
              "plugin list") [ -f "$STATE" ] && echo "  ❯ smalti@smalti" ;;
            esac
            exit 0
            """
        let claude = bin.appending(path: "claude")
        try Data(script.utf8).write(to: claude)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: claude.path(percentEncoded: false))
    }

    private func installer(path: String? = nil, failOn: String? = nil) -> ClaudePluginInstaller {
        var environment = [
            "PATH": path ?? "\(work.appending(path: "bin").path(percentEncoded: false)):/usr/bin:/bin",
            "LOG": log.path(percentEncoded: false), "STATE": work.appending(path: "state").path(percentEncoded: false),
        ]
        if let failOn { environment["FAIL_ON"] = failOn }
        return ClaudePluginInstaller(
            pluginSource: Self.pluginSource, installDirectory: installDirectory,
            runner: ShellCommandRunner(shell: ["/bin/sh", "-c"], environment: environment))
    }

    private var recorded: [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: realClaude.path(percentEncoded: false))))
    func pluginValidates() async {
        let runner = ShellCommandRunner(shell: ["/bin/sh", "-c"], environment: ["PATH": "/usr/bin:/bin"])

        let result = await runner.run([
            Self.realClaude.path(percentEncoded: false), "plugin", "validate",
            Self.pluginSource.path(percentEncoded: false),
        ])

        #expect(result.status == 0)
    }

    @Test func hooksCoverEveryAgentHook() throws {
        let hooks = try hookCommands()

        #expect(Set(hooks.keys) == Set(AgentHook.allCases.map(\.rawValue)))
    }

    /// Only notifications that mean "Claude needs you"; an `auth_success` must not turn a pane amber.
    @Test func notificationHookFiltersItsTypes() throws {
        let file = Self.pluginSource.appending(path: "plugins/smalti/hooks/hooks.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let entry = ((json?["hooks"] as? [String: [[String: Any]]])?["Notification"])?.first

        #expect(entry?["matcher"] as? String == "permission_prompt|idle_prompt|elicitation_dialog")
    }

    @Test func hookIsNoOpOutsideSmalti() async throws {
        let runner = ShellCommandRunner(shell: ["/bin/sh", "-c"], environment: ["PATH": "/usr/bin:/bin"])

        for command in try hookCommands().values {
            let result = await runner.runScript(command)
            #expect(result.status == 0)
            #expect(result.output.isEmpty)
        }
    }

    @Test func hookCallsTheCliOfItsSmalti() async throws {
        let cli = work.appending(path: "bin/claude")
        let runner = ShellCommandRunner(
            shell: ["/bin/sh", "-c"],
            environment: ["SMALTI_CLI": cli.path(percentEncoded: false), "LOG": log.path(percentEncoded: false)])

        _ = await runner.runScript(try #require(try hookCommands()["Stop"]))

        #expect(recorded == ["event Stop"])
    }

    @Test func installRunsMarketplaceAddThenInstall() async throws {
        try await installer().install()

        let directory = installDirectory.path(percentEncoded: false)
        #expect(
            recorded == [
                "plugin marketplace remove smalti", "plugin marketplace add \(directory)",
                "plugin install smalti@smalti",
            ])
        #expect(
            FileManager.default.fileExists(
                atPath: installDirectory.appending(path: ".claude-plugin/marketplace.json").path(percentEncoded: false))
        )
        #expect(
            FileManager.default.fileExists(
                atPath: installDirectory.appending(path: "plugins/smalti/hooks/hooks.json").path(percentEncoded: false))
        )
    }

    @Test func installReplacesAnOlderCopy() async throws {
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try Data("viejo".utf8).write(to: installDirectory.appending(path: "viejo.txt"))

        try await installer().install()

        #expect(
            !FileManager.default.fileExists(
                atPath: installDirectory.appending(path: "viejo.txt").path(percentEncoded: false)))
    }

    @Test func uninstallRunsUninstallThenRemove() async throws {
        try await installer().uninstall()

        #expect(recorded == ["plugin uninstall smalti@smalti", "plugin marketplace remove smalti"])
    }

    @Test func uninstallStillRemovesTheMarketplaceWhenThePluginIsGone() async {
        await #expect(throws: IntegrationError.self) {
            try await installer(failOn: "plugin uninstall smalti@smalti").uninstall()
        }

        #expect(recorded.last == "plugin marketplace remove smalti")
    }

    @Test func aShellThatCannotStartIsNotReportedAsMissingClaude() async {
        let runner = ShellCommandRunner(shell: ["/no/such/shell", "-c"], environment: [:])
        let broken = ClaudePluginInstaller(
            pluginSource: Self.pluginSource, installDirectory: installDirectory, runner: runner)

        await #expect(
            throws: IntegrationError.commandFailed(command: "/no/such/shell", output: "the shell could not start")
        ) {
            try await broken.install()
        }
    }

    @Test func aCommandThatNeverEndsIsStopped() async {
        let runner = ShellCommandRunner(shell: ["/bin/sh", "-c"], environment: [:], timeout: .milliseconds(300))
        let started = ContinuousClock.now

        let result = await runner.runScript("sleep 30")

        #expect(result.status != 0)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func failureReportsTheLastLineOfOutput() async {
        await #expect(
            throws: IntegrationError.commandFailed(
                command: "claude plugin install smalti@smalti", output: "boom\ndetalle")
        ) {
            try await installer(failOn: "plugin install smalti@smalti").install()
        }
    }

    @Test func missingClaudeIsReported() async {
        await #expect(throws: IntegrationError.harnessMissing(binary: "claude")) {
            try await installer(path: "/usr/bin:/bin").install()
        }
    }

    @Test func failingCommandIsReportedWithItsOutput() async {
        await #expect(
            throws: IntegrationError.commandFailed(
                command: "claude plugin install smalti@smalti", output: "boom\ndetalle")
        ) {
            try await installer(failOn: "plugin install smalti@smalti").install()
        }
    }

    @Test func installerSatisfiesTheIntegrationContract() async {
        await HarnessIntegrationContract.verify(installer())
    }

    /// `hooks.json`: hook name → its command.
    private func hookCommands() throws -> [String: String] {
        let file = Self.pluginSource.appending(path: "plugins/smalti/hooks/hooks.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let hooks = json?["hooks"] as? [String: [[String: Any]]] ?? [:]
        return hooks.compactMapValues { entries in
            (entries.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        }
    }
}
