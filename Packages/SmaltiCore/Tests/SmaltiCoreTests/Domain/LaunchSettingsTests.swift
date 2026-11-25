import Foundation
import SmaltiCore
import Testing

@Suite("LaunchSettings")
struct LaunchSettingsTests {
    private let home = URL(filePath: "/Users/simon")
    private let defaultState = URL(filePath: "/Users/simon/Library/Application Support/Smalti Dev")

    @Test func configPathArgumentIsHonoured() {
        let settings = LaunchSettings(
            arguments: ["SmaltiConfigPath": "/tmp/test.toml"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.configFile == URL(filePath: "/tmp/test.toml"))
    }

    @Test func missingConfigPathUsesTheUserConfigFile() {
        let settings = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(settings.configFile == URL(filePath: "/Users/simon/.config/smalti/config.toml"))
    }

    /// F5: `theme.toml` lives next to the config file, so tests that swap one also swap the other.
    @Test func themeFileSitsNextToTheConfigFile() {
        let settings = LaunchSettings(
            arguments: ["SmaltiConfigPath": "/tmp/run/config.toml"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.themeFile == URL(filePath: "/tmp/run/theme.toml"))
    }

    @Test func userThemeFileIsInTheSmaltiConfigFolder() {
        let settings = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(settings.themeFile == URL(filePath: "/Users/simon/.config/smalti/theme.toml"))
    }

    @Test func userZdotdirArgumentIsRead() {
        let settings = LaunchSettings(
            arguments: ["SmaltiUserZdotdir": "/tmp/zdot"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.userZdotdir == "/tmp/zdot")
    }

    @Test func emptyUserZdotdirIsAbsent() {
        let settings = LaunchSettings(
            arguments: ["SmaltiUserZdotdir": ""], home: home, defaultStateDirectory: defaultState)

        #expect(settings.userZdotdir == nil)
    }

    @Test func shellArgumentBecomesTheOverride() {
        let settings = LaunchSettings(
            arguments: ["SmaltiShellCommand": "/bin/zsh -f"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.shellOverride == .custom("/bin/zsh -f"))
    }

    @Test(arguments: [[:], ["SmaltiShellCommand": ""], ["SmaltiConfigPath": ""]])
    func emptyArgumentsAreIgnored(_ arguments: [String: String]) {
        let settings = LaunchSettings(arguments: arguments, home: home, defaultStateDirectory: defaultState)

        #expect(settings.shellOverride == nil)
        #expect(settings.configFile == URL(filePath: "/Users/simon/.config/smalti/config.toml"))
    }

    @Test func stateDirectoryDefaultsToGivenDirectory() {
        let settings = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(settings.stateDirectory == defaultState)
    }

    @Test func statePathArgumentOverridesDefault() {
        let settings = LaunchSettings(
            arguments: ["SmaltiStatePath": "/tmp/state"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.stateDirectory == URL(filePath: "/tmp/state"))
    }

    @Test func emptyStatePathIsIgnored() {
        let settings = LaunchSettings(
            arguments: ["SmaltiStatePath": ""], home: home, defaultStateDirectory: defaultState)

        #expect(settings.stateDirectory == defaultState)
    }

    @Test func claudeHomeArgumentWins() {
        let settings = LaunchSettings(
            arguments: ["SmaltiClaudeHome": "/tmp/claude", "CLAUDE_CONFIG_DIR": "/other"], home: home,
            defaultStateDirectory: defaultState)

        #expect(settings.claudeHome == URL(filePath: "/tmp/claude"))
    }

    @Test func claudeHomeFallsBackToConfigDirThenHome() {
        let withConfigDir = LaunchSettings(
            arguments: ["CLAUDE_CONFIG_DIR": "/Users/simon/.claude-alt"], home: home,
            defaultStateDirectory: defaultState)
        let plain = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(withConfigDir.claudeHome == URL(filePath: "/Users/simon/.claude-alt"))
        #expect(plain.claudeHome == URL(filePath: "/Users/simon/.claude"))
    }

    @Test func ollamaURLArgumentWins() {
        let custom = LaunchSettings(
            arguments: ["SmaltiOllamaURL": "http://127.0.0.1:1"], home: home, defaultStateDirectory: defaultState)
        let plain = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(custom.ollamaURL == URL(string: "http://127.0.0.1:1"))
        #expect(plain.ollamaURL == URL(string: "http://127.0.0.1:11434"))
    }

    // F6: harness homes and Neovim, swapped by the tests and read from the environment like Claude's.

    @Test func harnessHomesDefaultToTheUsersOwn() {
        let settings = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(settings.codexHome == URL(filePath: "/Users/simon/.codex"))
        #expect(settings.antigravityRoot == URL(filePath: "/Users/simon/.gemini/antigravity-cli"))
        #expect(settings.opencodeDataHome == URL(filePath: "/Users/simon/.local/share"))
        #expect(settings.opencodeDatabase == nil)
        #expect(settings.nvimConfigHome == URL(filePath: "/Users/simon/.config/nvim"))
        #expect(settings.nvimCommand == "nvim")
        #expect(settings.editorSocketDirectory == nil)
    }

    @Test func environmentMovesTheHomes() {
        let settings = LaunchSettings(
            arguments: [
                "CODEX_HOME": "/env/codex", "XDG_DATA_HOME": "/env/data", "XDG_CONFIG_HOME": "/env/config",
                "OPENCODE_DB": "/env/oc.db",
            ], home: home, defaultStateDirectory: defaultState)

        #expect(settings.codexHome == URL(filePath: "/env/codex"))
        #expect(settings.opencodeDataHome == URL(filePath: "/env/data"))
        #expect(settings.opencodeDatabase == URL(filePath: "/env/oc.db"))
        #expect(settings.nvimConfigHome == URL(filePath: "/env/config/nvim"))
    }

    @Test func testFlagsWinOverTheEnvironment() {
        let settings = LaunchSettings(
            arguments: [
                "CODEX_HOME": "/env/codex", "SmaltiCodexHome": "/t/codex", "SmaltiAntigravityHome": "/t/agy",
                "SmaltiOpenCodeDB": "/t/oc.db", "OPENCODE_DB": "/env/oc.db", "SmaltiNvimConfigHome": "/t/nvim",
                "SmaltiNvimCommand": "nvim --clean", "SmaltiEditorSocketDir": "/t/s",
            ], home: home, defaultStateDirectory: defaultState)

        #expect(settings.codexHome == URL(filePath: "/t/codex"))
        #expect(settings.antigravityRoot == URL(filePath: "/t/agy"))
        #expect(settings.opencodeDatabase == URL(filePath: "/t/oc.db"))
        #expect(settings.nvimConfigHome == URL(filePath: "/t/nvim"))
        #expect(settings.nvimCommand == "nvim --clean")
        #expect(settings.editorSocketDirectory == "/t/s")
    }

    @Test func relativeOpenCodeDatabaseIsIgnored() {
        let settings = LaunchSettings(
            arguments: ["OPENCODE_DB": "custom.db"], home: home, defaultStateDirectory: defaultState)

        #expect(settings.opencodeDatabase == nil)
    }

    // MARK: F7

    @Test func telemetryFlagsAreAbsentByDefault() {
        let settings = LaunchSettings(arguments: [:], home: home, defaultStateDirectory: defaultState)

        #expect(settings.managedSettings == nil)
        #expect(settings.telemetryProbe == nil)
    }

    @Test func telemetryFlagsAreRead() {
        let settings = LaunchSettings(
            arguments: ["SmaltiManagedSettings": "/t/managed.json", "SmaltiTelemetryProbe": "/t/probe.json"],
            home: home, defaultStateDirectory: defaultState)

        #expect(settings.managedSettings == URL(filePath: "/t/managed.json"))
        #expect(settings.telemetryProbe == URL(filePath: "/t/probe.json"))
        #expect(LaunchSettings.telemetryArgumentKeys == ["SmaltiManagedSettings", "SmaltiTelemetryProbe"])
    }
}
