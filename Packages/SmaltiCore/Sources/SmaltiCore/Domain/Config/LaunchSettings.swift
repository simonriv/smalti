import Foundation

/// Launch arguments, resolved once at startup. Both exist so automated tests never touch the user's own setup:
/// `SmaltiConfigPath` swaps `~/.config/smalti/config.toml`, and `SmaltiShellCommand` runs a shell without startup
/// files (spec R2), and `SmaltiStatePath` swaps the app's state directory (F2). Empty values count as absent.
public struct LaunchSettings: Equatable, Sendable {
    public static let configPathKey = "SmaltiConfigPath"
    public static let shellCommandKey = "SmaltiShellCommand"
    public static let statePathKey = "SmaltiStatePath"
    public static let claudeHomeKey = "SmaltiClaudeHome"
    /// Not a launch argument: the composition root copies this environment variable into the same map.
    public static let claudeConfigDirKey = "CLAUDE_CONFIG_DIR"
    public static let ollamaURLKey = "SmaltiOllamaURL"
    public static let defaultOllamaURL = "http://127.0.0.1:11434"
    /// Relative to the home directory.
    public static let userConfigPath = ".config/smalti/config.toml"

    public let configFile: URL
    public let shellOverride: TerminalCommand?
    /// Where the app keeps its sessions, layouts and socket: the build's own directory unless a test swaps it.
    public let stateDirectory: URL
    /// Claude Code's home (transcripts and live sessions); tests point it at a fixture and never read the real one.
    public let claudeHome: URL
    /// Ollama's local API.
    public let ollamaURL: URL

    public init(arguments: [String: String], home: URL, defaultStateDirectory: URL) {
        let value = { (key: String) in arguments[key].flatMap { $0.isEmpty ? nil : $0 } }
        configFile = value(Self.configPathKey).map { URL(filePath: $0) } ?? home.appending(path: Self.userConfigPath)
        shellOverride = value(Self.shellCommandKey).map { .custom($0) }
        stateDirectory = value(Self.statePathKey).map { URL(filePath: $0) } ?? defaultStateDirectory
        claudeHome =
            (value(Self.claudeHomeKey) ?? value(Self.claudeConfigDirKey)).map { URL(filePath: $0) }
            ?? home.appending(path: ".claude")
        ollamaURL = value(Self.ollamaURLKey).flatMap { URL(string: $0) } ?? Self.ollamaFallback
    }

    // A literal that always parses; the fallback only exists to keep the type non-optional.
    private static let ollamaFallback = URL(string: defaultOllamaURL) ?? URL(filePath: "/")
}
