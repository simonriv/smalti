import SmaltiCore
import Testing

/// What a `ConfigStoreHarness` can put at the store's source before it is read.
public enum ConfigScenario: Sendable {
    /// There is no configuration at all.
    case missing
    /// Valid: `shell = .custom("/bin/zsh -f")` and `defaultLayout = .columns`; everything else default.
    case customShellAndColumns
    /// The source exists but cannot be read as a configuration.
    case invalid
}

/// Lets the shared contract drive any `ConfigStore` implementation.
@MainActor
public protocol ConfigStoreHarness {
    func makeStore() -> any ConfigStore
    func write(_ scenario: ConfigScenario)
}

/// Behavior every `ConfigStore` must have. Run it from each implementation's tests.
public enum ConfigStoreContract {
    public static let customConfig = SmaltiConfig(
        appearance: SmaltiConfig.defaults.appearance, defaultLayout: .columns, shell: .custom("/bin/zsh -f"),
        keys: SmaltiConfig.defaults.keys)

    @MainActor
    public static func verify(_ harness: some ConfigStoreHarness) throws {
        try missingSourceGivesDefaults(harness)
        try validSourceGivesItsValues(harness)
        try failedReloadKeepsLastValid(harness)
    }

    @MainActor
    private static func missingSourceGivesDefaults(_ harness: some ConfigStoreHarness) throws {
        harness.write(.missing)
        let store = harness.makeStore()

        let reloaded = try store.reload()

        #expect(reloaded == .defaults)
        #expect(store.current() == .defaults)
    }

    @MainActor
    private static func validSourceGivesItsValues(_ harness: some ConfigStoreHarness) throws {
        harness.write(.customShellAndColumns)
        let store = harness.makeStore()

        let reloaded = try store.reload()

        #expect(reloaded == customConfig)
        #expect(store.current() == customConfig)
    }

    @MainActor
    private static func failedReloadKeepsLastValid(_ harness: some ConfigStoreHarness) throws {
        harness.write(.customShellAndColumns)
        let store = harness.makeStore()
        _ = try store.reload()
        harness.write(.invalid)

        #expect(throws: ConfigError.self) { try store.reload() }

        #expect(store.current() == customConfig)
    }
}
