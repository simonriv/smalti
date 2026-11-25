/// Port to wherever the configuration lives (a TOML file today).
@MainActor
public protocol ConfigStore: AnyObject {
    /// The last valid configuration, or `SmaltiConfig.defaults` when there has been none. Never fails.
    func current() -> SmaltiConfig
    /// Reads the source again. On failure it throws and `current()` keeps the previous configuration.
    func reload() throws(ConfigError) -> SmaltiConfig
    /// What the last successful read noticed without failing (F5: keys written in both files).
    func warnings() -> [ConfigWarning]
}

extension ConfigStore {
    public func warnings() -> [ConfigWarning] { [] }
}

/// Something a valid configuration does that the user should know about.
public enum ConfigWarning: Equatable, Sendable {
    /// Keys set in both `config.toml` and `theme.toml`; `theme.toml` wins (spec F5).
    case duplicatedKeys([String])
    /// F7.6: the file was written for a newer Smalti; what this build does not know was ignored.
    case newerFormat(file: String, version: Int, ignored: [String])

    public var message: String {
        switch self {
        case .duplicatedKeys(let keys): "theme.toml manda sobre config.toml en: " + keys.joined(separator: ", ")
        case .newerFormat(let file, let version, let ignored):
            "\(file) es de una versión más nueva de Smalti (\(version)): se ignoran " + ignored.joined(separator: ", ")
        }
    }
}
