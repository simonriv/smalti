import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

@MainActor
@Suite("Ghostty config loader")
struct GhosttyConfigLoaderTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "smalti-ghostty-\(UUID()).conf")

    init() throws {
        try TestGhostty.initialize()
    }

    @Test func loadsGeneratedConfigWithoutDiagnostics() throws {
        _ = try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file)
    }

    @Test func applyingAppearanceReloadsWithoutDiagnostics() throws {
        let runtime = try GhosttyRuntime(
            config: try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file))
        let engine = GhosttyTerminalEngine(runtime: runtime)
        let pane = try engine.open(
            TerminalSessionSpec(workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f")))
        defer { engine.close(pane) }
        var settings = AppearanceSettings.obsidian
        settings.fontSize = 15
        let appearance = Theme.obsidian.applying(settings).terminal

        try runtime.apply(appearance)

        #expect(try String(contentsOf: file, encoding: .utf8) == GhosttyConfigText.render(appearance))
    }

    @Test func failedApplyLeavesConfigFileUntouched() throws {
        let runtime = try GhosttyRuntime(
            config: try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file))
        let before = try Data(contentsOf: file)

        #expect(throws: TerminalEngineError.self) { try runtime.reload(configText: "not-a-real-key = 1\n") }

        #expect(try Data(contentsOf: file) == before)
    }

    @Test func failedApplyLeavesNoTemporaryFile() throws {
        let runtime = try GhosttyRuntime(
            config: try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file))
        let directory = file.deletingLastPathComponent()

        _ = try? runtime.reload(configText: "not-a-real-key = 1\n")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasPrefix(".\(file.lastPathComponent).") }
        #expect(leftovers.isEmpty)
    }

    @Test func invalidKeyThrowsWithDiagnostics() {
        #expect {
            _ = try GhosttyConfig.load(text: "not-a-real-key = 1\n", writingTo: file)
        } throws: { error in
            guard case TerminalEngineError.configurationInvalid(let diagnostics) = error else { return false }
            return diagnostics.contains { $0.contains("not-a-real-key") }
        }
    }
}
