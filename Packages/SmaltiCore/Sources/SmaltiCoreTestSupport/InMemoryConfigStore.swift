import SmaltiCore

/// A `ConfigStore` whose source is a value tests can replace.
@MainActor
public final class InMemoryConfigStore: ConfigStore {
    private var source: Result<SmaltiConfig, ConfigError>
    private var lastValid = SmaltiConfig.defaults

    public init(source: Result<SmaltiConfig, ConfigError> = .success(.defaults)) {
        self.source = source
    }

    public func replaceSource(with source: Result<SmaltiConfig, ConfigError>) {
        self.source = source
    }

    public func current() -> SmaltiConfig {
        lastValid
    }

    public func reload() throws(ConfigError) -> SmaltiConfig {
        lastValid = try source.get()
        return lastValid
    }
}

/// Harness for `InMemoryConfigStore`, used to run the shared contract against it.
@MainActor
public final class InMemoryConfigStoreHarness: ConfigStoreHarness {
    private var scenario = ConfigScenario.missing
    private var stores: [InMemoryConfigStore] = []

    public init() {}

    public func makeStore() -> any ConfigStore {
        let store = InMemoryConfigStore(source: Self.source(for: scenario))
        stores.append(store)
        return store
    }

    /// Changes what every store made so far, and the next ones, will read.
    public func write(_ scenario: ConfigScenario) {
        self.scenario = scenario
        for store in stores {
            store.replaceSource(with: Self.source(for: scenario))
        }
    }

    private static func source(for scenario: ConfigScenario) -> Result<SmaltiConfig, ConfigError> {
        switch scenario {
        case .missing: .success(.defaults)
        case .customShellAndColumns: .success(ConfigStoreContract.customConfig)
        case .invalid:
            .failure(ConfigError(file: "config.toml", line: 3, key: "font_size", problem: .expectedNumber))
        }
    }
}
