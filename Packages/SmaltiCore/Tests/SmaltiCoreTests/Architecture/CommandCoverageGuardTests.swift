import Foundation
import SmaltiCore
import Testing

/// F4.5 (block 1 review): every command the app ships has somewhere to go in the app — a tiling action, a view
/// command or an app command in `TilingController` — so none ends in "unknown command". Numbered, directional and
/// layout commands are built in families there and are left to their own tests.
@Suite("Command coverage guard")
struct CommandCoverageGuardTests {
    private static let controller = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Architecture
        .deletingLastPathComponent()  // SmaltiCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SmaltiCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "App/Smalti/TilingController.swift")

    /// "window.new" → "windowNew", "secureInput.toggle" → "secureInputToggle".
    static func swiftName(_ rawValue: String) -> String {
        let parts = rawValue.split(separator: ".")
        return parts.enumerated().map { index, part in
            index == 0 ? String(part) : part.prefix(1).uppercased() + part.dropFirst()
        }.joined()
    }

    private static func isFamily(_ command: CommandID) -> Bool {
        let raw = command.rawValue
        let directions = ["left", "right", "up", "down"]
        return raw.hasPrefix("layout.") || raw.contains(where: \.isNumber)
            || directions.contains { raw.hasSuffix(".\($0)") }
    }

    @Test func nameFollowsTheRawValue() {
        #expect(Self.swiftName("window.new") == "windowNew")
        #expect(Self.swiftName("claude.integration.install") == "claudeIntegrationInstall")
        #expect(Self.swiftName("terminal.selectAll") == "terminalSelectAll")
    }

    @Test func everyStandardCommandHasAnActionInTheApp() throws {
        let source = try String(contentsOf: Self.controller, encoding: .utf8)

        let missing = CommandID.allStandard.filter { !Self.isFamily($0) }.filter {
            !source.contains(".\(Self.swiftName($0.rawValue))")
        }

        #expect(missing.isEmpty, "no action in TilingController for: \(missing.map(\.rawValue))")
    }
}
