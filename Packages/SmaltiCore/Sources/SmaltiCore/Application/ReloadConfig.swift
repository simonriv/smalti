/// The configuration in effect after a reload attempt, and why the attempt failed, if it did.
public struct ConfigReload: Equatable, Sendable {
    public let config: SmaltiConfig
    public let error: ConfigError?
    public let warnings: [ConfigWarning]

    public init(config: SmaltiConfig, error: ConfigError?, warnings: [ConfigWarning] = []) {
        self.config = config
        self.error = error
        self.warnings = warnings
    }
}

/// Re-reads the configuration; on failure the previous configuration stays in effect.
@MainActor
public struct ReloadConfig {
    private let store: any ConfigStore

    public init(store: any ConfigStore) {
        self.store = store
    }

    public func execute() -> ConfigReload {
        do {
            let config = try store.reload()
            return ConfigReload(config: config, error: nil, warnings: store.warnings())
        } catch {
            return ConfigReload(config: store.current(), error: error)
        }
    }
}
