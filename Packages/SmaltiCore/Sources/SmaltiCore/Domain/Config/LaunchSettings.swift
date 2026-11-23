import Foundation

/// Launch arguments, resolved once at startup. Both exist so automated tests never touch the user's own setup:
/// `SmaltiConfigPath` swaps `~/.config/smalti/config.toml`, and `SmaltiShellCommand` runs a shell without startup
/// files (spec R2), and `SmaltiStatePath` swaps the app's state directory (F2). Empty values count as absent.
public struct LaunchSettings: Equatable, Sendable {
    public static let configPathKey = "SmaltiConfigPath"
    public static let shellCommandKey = "SmaltiShellCommand"
    public static let statePathKey = "SmaltiStatePath"
    /// Relative to the home directory.
    public static let userConfigPath = ".config/smalti/config.toml"

    public let configFile: URL
    public let shellOverride: TerminalCommand?
    /// Where the app keeps its sessions, layouts and socket: the build's own directory unless a test swaps it.
    public let stateDirectory: URL

    public init(arguments: [String: String], home: URL, defaultStateDirectory: URL) {
        let value = { (key: String) in arguments[key].flatMap { $0.isEmpty ? nil : $0 } }
        configFile = value(Self.configPathKey).map { URL(filePath: $0) } ?? home.appending(path: Self.userConfigPath)
        shellOverride = value(Self.shellCommandKey).map { .custom($0) }
        stateDirectory = value(Self.statePathKey).map { URL(filePath: $0) } ?? defaultStateDirectory
    }
}
