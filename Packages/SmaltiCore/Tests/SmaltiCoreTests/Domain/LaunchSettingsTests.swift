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
}
