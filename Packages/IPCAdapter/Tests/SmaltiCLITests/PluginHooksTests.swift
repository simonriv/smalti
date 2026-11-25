import Foundation
import IPCAdapter
import SmaltiCore
import Testing

@testable import smalti

/// The plugin's hooks as `App/ClaudePlugin` ships them (spec F7.5, C3).
@Suite("Plugin hooks")
struct PluginHooksTests {
    private static let plugin = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../App/ClaudePlugin/plugins/smalti").standardized

    private func hooks() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.plugin.appending(path: "hooks/hooks.json"))
        return try #require(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["hooks"] as? [String: Any])
    }

    private func entry(_ hook: String) throws -> [String: Any] {
        let groups = try #require(try hooks()[hook] as? [[String: Any]])
        return try #require((groups.first?["hooks"] as? [[String: Any]])?.first)
    }

    @Test func preToolUseGuardsAndFailsClosed() throws {
        let preToolUse = try entry("PreToolUse")

        #expect((preToolUse["command"] as? String)?.contains("guard PreToolUse") == true)
        #expect(preToolUse["onFailure"] as? String == "block")
        #expect(preToolUse["timeout"] as? Int == 660)
    }

    @Test func deadlinesNestHookOverCLIOverServerOverApp() throws {
        let hook = try #require(try entry("PreToolUse")["timeout"] as? Int)

        #expect(Duration.seconds(hook) > GuardCommand.deadline)
        #expect(GuardCommand.deadline > .seconds(UnixSocketTelemetry.guardWaitSeconds))
        #expect(Double(UnixSocketTelemetry.guardWaitSeconds) > AgentApprovals.standardTimeout)
    }

    @Test func otherHooksStillOnlyReport() throws {
        for hook in ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Notification", "Stop"] {
            let command = try entry(hook)["command"] as? String
            #expect(command == "\"${SMALTI_CLI:-true}\" event \(hook)")
            #expect(try entry(hook)["onFailure"] == nil)
        }
    }

    /// Runs the PreToolUse hook's command as Claude does (`sh -c`) with `SMALTI_CLI` set to `cli`.
    private func runHook(cli: String) throws -> (status: Int32, log: String) {
        let command = try #require(try entry("PreToolUse")["command"] as? String)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["SMALTI_CLI": cli, "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"tool_name":"Bash"}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let log = (try? String(contentsOfFile: cli + ".log", encoding: .utf8)) ?? ""
        return (process.terminationStatus, log)
    }

    private func fakeCLI(_ body: String) throws -> String {
        let path = NSTemporaryDirectory() + "smalti-fake-cli-\(UUID().uuidString)"
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: URL(filePath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// Review 1 (I8): a CLI from before the guard answers `guard` with a usage error (64); the hook then reports the
    /// event as F2 did instead of blocking every tool of that Smalti.
    @Test func oldCLIFallsBackToEvent() throws {
        let cli = try fakeCLI(
            #"echo "$*" >> "$0.log"; [ "$1" = guard ] && exit 64; cat > /dev/null; exit 0"#)

        let result = try runHook(cli: cli)

        #expect(result.status == 0)
        #expect(result.log == "guard PreToolUse\nevent PreToolUse\n")
    }

    @Test func guardFailureOtherThanUsageStillFails() throws {
        let cli = try fakeCLI(#"echo "$*" >> "$0.log"; exit 3"#)

        let result = try runHook(cli: cli)

        #expect(result.status == 3)
        #expect(result.log == "guard PreToolUse\n")
    }

    @Test func missingCLIFailsSoOnFailureBlocks() throws {
        #expect(try runHook(cli: "/nonexistent/smalti").status == 127)
    }

    @Test func outsideSmaltiDoesNothing() throws {
        let command = try #require(try entry("PreToolUse")["command"] as? String)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    @Test func pluginVersionIsTwo() throws {
        let data = try Data(contentsOf: Self.plugin.appending(path: ".claude-plugin/plugin.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["version"] as? String == "0.2.0")
    }
}
