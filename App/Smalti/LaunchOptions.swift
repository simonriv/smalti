import Foundation
import SmaltiCore

/// Launch arguments read once at startup. Both exist so automated tests never touch Simón's own setup:
/// `-SmaltiConfigPath <path>` swaps `~/.config/smalti/config.toml`, and `-SmaltiShellCommand <command>` runs a shell
/// without startup files (his login shell attaches to a shared tmux session).
struct LaunchOptions {
    let configFile: URL
    let shellOverride: TerminalCommand?

    static func current(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(
            configFile: path(defaults, "SmaltiConfigPath").map { URL(filePath: $0) } ?? defaultConfigFile,
            shellOverride: path(defaults, "SmaltiShellCommand").map { .custom($0) })
    }

    static var defaultConfigFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/smalti/config.toml")
    }

    private static func path(_ defaults: UserDefaults, _ key: String) -> String? {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
        return value
    }
}
