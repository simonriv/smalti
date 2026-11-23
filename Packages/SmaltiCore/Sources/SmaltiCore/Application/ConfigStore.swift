/// Port to wherever the configuration lives (a TOML file today).
@MainActor
public protocol ConfigStore: AnyObject {
    /// The last valid configuration, or `SmaltiConfig.defaults` when there has been none. Never fails.
    func current() -> SmaltiConfig
    /// Reads the source again. On failure it throws and `current()` keeps the previous configuration.
    func reload() throws(ConfigError) -> SmaltiConfig
}
