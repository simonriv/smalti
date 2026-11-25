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

        #expect(preToolUse["command"] as? String == "\"${SMALTI_CLI:-true}\" guard PreToolUse")
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

    @Test func pluginVersionIsTwo() throws {
        let data = try Data(contentsOf: Self.plugin.appending(path: ".claude-plugin/plugin.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["version"] as? String == "0.2.0")
    }
}
