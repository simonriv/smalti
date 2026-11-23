/// The configuration in effect after a reload attempt, and why the attempt failed, if it did.
public struct ConfigReload: Equatable, Sendable {
    public let config: SmaltiConfig
    public let error: ConfigError?

    public init(config: SmaltiConfig, error: ConfigError?) {
        self.config = config
        self.error = error
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
            return ConfigReload(config: try store.reload(), error: nil)
        } catch {
            return ConfigReload(config: store.current(), error: error)
        }
    }
}
