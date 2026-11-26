import Foundation
import SmaltiCore
import Testing

/// F4.5 (block 1 review): every command the app ships has somewhere to go in the app — a tiling action, a view
/// command or an app command in `TilingController` — so none ends in "unknown command". Numbered, directional and
/// layout commands are built in families there and are left to their own tests. Final review: an app or view command
/// is handled by its own `case` where it lands (`AppComposition`, `WindowComposition`), never by a `default`.
@Suite("Command coverage guard")
struct CommandCoverageGuardTests {
    private static let app = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Architecture
        .deletingLastPathComponent()  // SmaltiCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SmaltiCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "App/Smalti")
    private static let controller = app.appending(path: "TilingController.swift")
    private static var isInRepository: Bool {
        FileManager.default.fileExists(atPath: controller.path(percentEncoded: false))
    }

    /// The commands of one `static let <name>: Set<CommandID> = [...]` in `source`, by their Swift names.
    static func commandSet(_ name: String, in source: String) -> [String] {
        guard let start = source.range(of: "static let \(name): Set<CommandID> = ["),
            let end = source[start.upperBound...].firstIndex(of: "]")
        else { return [] }
        return source[start.upperBound..<end].matches(of: #/\.([A-Za-z]+)/#).map { String($0.output.1) }
    }

    /// `source` has a `case` that names `.command` (alone or in a list).
    static func hasCase(for command: String, in source: String) -> Bool {
        source.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case "), let colon = trimmed.firstIndex(of: ":") else { return false }
            return trimmed[..<colon].split(whereSeparator: { ", ".contains($0) }).contains { $0 == ".\(command)" }
        }
    }

    /// "window.new" → "windowNew", "secureInput.toggle" → "secureInputToggle".
    static func swiftName(_ rawValue: String) -> String {
        let parts = rawValue.split(separator: ".")
        return parts.enumerated().map { index, part in
            index == 0 ? String(part) : part.prefix(1).uppercased() + part.dropFirst()
        }.joined()
    }

    /// Commands of a phase in progress whose app action lands in a later task; empty between phases.
    /// F8: wired in the app by T8 of the plan.
    static let pendingInApp: Set<CommandID> = Set(CommandID.processes)

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

    @Test func commandSetAndCaseAreFound() {
        let source = "static let appCommands: Set<CommandID> = [\n    .windowNew, .appAbout,\n]\ncase .appAbout: x()"

        #expect(Self.commandSet("appCommands", in: source) == ["windowNew", "appAbout"])
        #expect(Self.hasCase(for: "appAbout", in: source))
        #expect(!Self.hasCase(for: "windowNew", in: source))
        #expect(Self.hasCase(for: "searchNext", in: "        case .searchNext, .searchPrevious:"))
    }

    @Test(.enabled(if: isInRepository))
    func everyAppCommandHasItsOwnCaseInAppComposition() throws {
        let commands = Self.commandSet("appCommands", in: try String(contentsOf: Self.controller, encoding: .utf8))
        let source = try String(contentsOf: Self.app.appending(path: "AppComposition.swift"), encoding: .utf8)

        #expect(!commands.isEmpty)
        #expect(commands.filter { !Self.hasCase(for: $0, in: source) }.isEmpty)
    }

    @Test(.enabled(if: isInRepository))
    func everyViewCommandHasItsOwnCaseInWindowComposition() throws {
        let commands = Self.commandSet("viewCommands", in: try String(contentsOf: Self.controller, encoding: .utf8))
        let source = try String(contentsOf: Self.app.appending(path: "WindowComposition.swift"), encoding: .utf8)

        #expect(!commands.isEmpty)
        #expect(commands.filter { !Self.hasCase(for: $0, in: source) }.isEmpty)
    }

    /// Block 1 review (M3): a pending command that already has an action must leave `pendingInApp`, or the guard
    /// would stop watching it for good.
    @Test(.enabled(if: isInRepository))
    func pendingCommandsHaveNoActionYet() throws {
        let source = try String(contentsOf: Self.controller, encoding: .utf8)

        let wired = Self.pendingInApp.filter { source.contains(".\(Self.swiftName($0.rawValue))") }

        #expect(wired.isEmpty, "remove from pendingInApp: \(wired.map(\.rawValue))")
    }

    /// Runs inside the repository only: mutation testing copies this package alone, without the app.
    @Test(.enabled(if: isInRepository))
    func everyStandardCommandHasAnActionInTheApp() throws {
        let source = try String(contentsOf: Self.controller, encoding: .utf8)

        let missing = CommandID.allStandard.filter { !Self.isFamily($0) && !Self.pendingInApp.contains($0) }.filter {
            !source.contains(".\(Self.swiftName($0.rawValue))")
        }

        #expect(missing.isEmpty, "no action in TilingController for: \(missing.map(\.rawValue))")
    }
}
