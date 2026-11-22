import Foundation
import SmaltiCore
import Testing

@Suite("LaunchSettings")
struct LaunchSettingsTests {
    private let home = URL(filePath: "/Users/simon")

    @Test func configPathArgumentIsHonoured() {
        let settings = LaunchSettings(arguments: ["SmaltiConfigPath": "/tmp/test.toml"], home: home)

        #expect(settings.configFile == URL(filePath: "/tmp/test.toml"))
    }

    @Test func missingConfigPathUsesTheUserConfigFile() {
        let settings = LaunchSettings(arguments: [:], home: home)

        #expect(settings.configFile == URL(filePath: "/Users/simon/.config/smalti/config.toml"))
    }

    @Test func shellArgumentBecomesTheOverride() {
        let settings = LaunchSettings(arguments: ["SmaltiShellCommand": "/bin/zsh -f"], home: home)

        #expect(settings.shellOverride == .custom("/bin/zsh -f"))
    }

    @Test(arguments: [[:], ["SmaltiShellCommand": ""], ["SmaltiConfigPath": ""]])
    func emptyArgumentsAreIgnored(_ arguments: [String: String]) {
        let settings = LaunchSettings(arguments: arguments, home: home)

        #expect(settings.shellOverride == nil)
        #expect(settings.configFile == URL(filePath: "/Users/simon/.config/smalti/config.toml"))
    }
}
