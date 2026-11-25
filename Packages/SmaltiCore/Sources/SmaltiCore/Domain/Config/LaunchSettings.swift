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
    /// F4: the user ZDOTDIR the panes' zsh restores after Ghostty's integration; tests point it at an empty folder.
    public static let userZdotdirKey = "SmaltiUserZdotdir"
    public static let defaultOllamaURL = "http://127.0.0.1:11434"
    /// F6: the harnesses' and Neovim's homes. The `Smalti…` arguments are for tests; the environment variables are
    /// the harnesses' own (the composition root copies them into the same map).
    public static let codexHomeKey = "SmaltiCodexHome"
    public static let codexHomeEnvironmentKey = "CODEX_HOME"
    public static let antigravityHomeKey = "SmaltiAntigravityHome"
    public static let opencodeDatabaseKey = "SmaltiOpenCodeDB"
    public static let opencodeDatabaseEnvironmentKey = "OPENCODE_DB"
    public static let dataHomeEnvironmentKey = "XDG_DATA_HOME"
    public static let configHomeEnvironmentKey = "XDG_CONFIG_HOME"
    public static let nvimConfigHomeKey = "SmaltiNvimConfigHome"
    public static let nvimCommandKey = "SmaltiNvimCommand"
    public static let editorSocketDirectoryKey = "SmaltiEditorSocketDir"
    /// F7 (tests): the managed Claude settings to check instead of the machine's, and a file where the app writes
    /// the telemetry receiver's status.
    public static let managedSettingsKey = "SmaltiManagedSettings"
    public static let telemetryProbeKey = "SmaltiTelemetryProbe"
    public static let telemetryArgumentKeys = [managedSettingsKey, telemetryProbeKey]
    /// F7.5 (tests): how long an approval waits, in seconds.
    public static let approvalTimeoutKey = "SmaltiApprovalTimeoutSeconds"
    public static let guardArgumentKeys = [approvalTimeoutKey]
    /// Every key the composition root reads, arguments and environment alike.
    public static let harnessArgumentKeys = [
        codexHomeKey, antigravityHomeKey, opencodeDatabaseKey, nvimConfigHomeKey, nvimCommandKey,
        editorSocketDirectoryKey,
    ]
    public static let harnessEnvironmentKeys = [
        codexHomeEnvironmentKey, opencodeDatabaseEnvironmentKey, dataHomeEnvironmentKey, configHomeEnvironmentKey,
    ]
    /// Relative to the home directory.
    public static let userConfigPath = ".config/smalti/config.toml"

    public let configFile: URL
    /// F5: where the UI writes the appearance, next to the config file (`~/.config/smalti/theme.toml`).
    public var themeFile: URL { configFile.deletingLastPathComponent().appending(path: Self.themeFileName) }
    public static let themeFileName = "theme.toml"
    public let shellOverride: TerminalCommand?
    /// Where the app keeps its sessions, layouts and socket: the build's own directory unless a test swaps it.
    public let stateDirectory: URL
    /// Claude Code's home (transcripts and live sessions); tests point it at a fixture and never read the real one.
    public let claudeHome: URL
    /// Ollama's local API.
    public let ollamaURL: URL
    /// Overrides the app's own `ZDOTDIR` for the panes (tests only).
    public let userZdotdir: String?
    /// F6: `$CODEX_HOME`.
    public let codexHome: URL
    /// F6: Antigravity's `antigravity-cli` folder.
    public let antigravityRoot: URL
    /// F6: where OpenCode keeps its data (`$XDG_DATA_HOME`), and its database when named outright.
    public let opencodeDataHome: URL
    public let opencodeDatabase: URL?
    /// F6: Neovim's config folder (the claudecode.nvim installer writes there), the command its panes run and,
    /// for tests, where their sockets go.
    public let nvimConfigHome: URL
    public let nvimCommand: String
    public let editorSocketDirectory: String?
    /// F7: nil uses the machine's managed settings; tests point it at a temporary file.
    public let managedSettings: URL?
    public let telemetryProbe: URL?
    /// F7.5: how long a guarded command waits for the user before it is denied.
    public let approvalTimeout: Double

    public init(arguments: [String: String], home: URL, defaultStateDirectory: URL) {
        let value = { (key: String) in arguments[key].flatMap { $0.isEmpty ? nil : $0 } }
        configFile = value(Self.configPathKey).map { URL(filePath: $0) } ?? home.appending(path: Self.userConfigPath)
        shellOverride = value(Self.shellCommandKey).map { .custom($0) }
        stateDirectory = value(Self.statePathKey).map { URL(filePath: $0) } ?? defaultStateDirectory
        claudeHome =
            (value(Self.claudeHomeKey) ?? value(Self.claudeConfigDirKey)).map { URL(filePath: $0) }
            ?? home.appending(path: ".claude")
        ollamaURL = value(Self.ollamaURLKey).flatMap { URL(string: $0) } ?? Self.ollamaFallback
        userZdotdir = value(Self.userZdotdirKey)
        codexHome =
            (value(Self.codexHomeKey) ?? value(Self.codexHomeEnvironmentKey)).map { URL(filePath: $0) }
            ?? home.appending(path: ".codex")
        antigravityRoot =
            value(Self.antigravityHomeKey).map { URL(filePath: $0) } ?? home.appending(path: ".gemini/antigravity-cli")
        opencodeDataHome =
            value(Self.dataHomeEnvironmentKey).map { URL(filePath: $0) } ?? home.appending(path: ".local/share")
        opencodeDatabase = (value(Self.opencodeDatabaseKey) ?? value(Self.opencodeDatabaseEnvironmentKey))
            .flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
        nvimConfigHome =
            value(Self.nvimConfigHomeKey).map { URL(filePath: $0) }
            ?? (value(Self.configHomeEnvironmentKey).map { URL(filePath: $0) } ?? home.appending(path: ".config"))
            .appending(path: "nvim")
        nvimCommand = value(Self.nvimCommandKey) ?? "nvim"
        editorSocketDirectory = value(Self.editorSocketDirectoryKey)
        managedSettings = value(Self.managedSettingsKey).map { URL(filePath: $0) }
        telemetryProbe = value(Self.telemetryProbeKey).map { URL(filePath: $0) }
        approvalTimeout =
            value(Self.approvalTimeoutKey).flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            ?? AgentApprovals.standardTimeout
    }

    // A literal that always parses; the fallback only exists to keep the type non-optional.
    private static let ollamaFallback = URL(string: defaultOllamaURL) ?? URL(filePath: "/")
}
