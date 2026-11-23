import Foundation

/// Launch arguments, resolved once at startup. Both exist so automated tests never touch the user's own setup:
/// `SmaltiConfigPath` swaps `~/.config/smalti/config.toml`, and `SmaltiShellCommand` runs a shell without startup
/// files (spec R2). Empty values count as absent.
public struct LaunchSettings: Equatable, Sendable {
    public static let configPathKey = "SmaltiConfigPath"
    public static let shellCommandKey = "SmaltiShellCommand"
    /// Relative to the home directory.
    public static let userConfigPath = ".config/smalti/config.toml"

    public let configFile: URL
    public let shellOverride: TerminalCommand?

    public init(arguments: [String: String], home: URL) {
        let value = { (key: String) in arguments[key].flatMap { $0.isEmpty ? nil : $0 } }
        configFile = value(Self.configPathKey).map { URL(filePath: $0) } ?? home.appending(path: Self.userConfigPath)
        shellOverride = value(Self.shellCommandKey).map { .custom($0) }
    }
}
