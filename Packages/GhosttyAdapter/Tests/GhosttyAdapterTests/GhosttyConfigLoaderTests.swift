import Foundation
import GhosttyAdapter
import SmaltiCore
import Testing

@MainActor
@Suite("Ghostty config loader")
struct GhosttyConfigLoaderTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "smalti-ghostty-\(UUID()).conf")

    init() throws {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: nil)
    }

    @Test func loadsGeneratedConfigWithoutDiagnostics() throws {
        _ = try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file)
    }

    @Test func applyingAppearanceReloadsWithoutDiagnostics() throws {
        let runtime = try GhosttyRuntime(
            config: try GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: file))
        var settings = AppearanceSettings.obsidian
        settings.fontSize = 15
        let appearance = Theme.obsidian.applying(settings).terminal

        try runtime.apply(appearance)

        #expect(try String(contentsOf: file, encoding: .utf8) == GhosttyConfigText.render(appearance))
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
