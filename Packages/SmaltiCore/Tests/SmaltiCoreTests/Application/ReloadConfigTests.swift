import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("ReloadConfig")
struct ReloadConfigTests {
    private var customConfig: SmaltiConfig {
        var config = SmaltiConfig.defaults
        config.defaultLayout = .columns
        return config
    }

    @Test func reloadReturnsNewConfig() {
        let store = InMemoryConfigStore(source: .success(customConfig))

        let reload = ReloadConfig(store: store).execute()

        #expect(reload.config == customConfig)
        #expect(reload.error == nil)
    }

    @Test func failedReloadKeepsPreviousAndReportsError() {
        let store = InMemoryConfigStore(source: .success(customConfig))
        _ = ReloadConfig(store: store).execute()
        let failure = ConfigError(file: "config.toml", line: 3, key: "font_size", problem: .expectedNumber)
        store.replaceSource(with: .failure(failure))

        let reload = ReloadConfig(store: store).execute()

        #expect(reload.config == customConfig)
        #expect(reload.error == failure)
    }
}
