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
}
