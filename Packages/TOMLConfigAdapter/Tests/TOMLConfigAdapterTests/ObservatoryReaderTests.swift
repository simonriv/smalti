import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

@Suite("Observatory models in the TOML")
struct ObservatoryReaderTests {
    private let opus = ModelID(rawValue: "claude-opus-5-5")
    private let next = ModelID(rawValue: "claude-next-1")

    private func parse(_ text: String) throws(ConfigError) -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: "config.toml")
    }

    private func error(parsing text: String) -> ConfigError? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error
        }
    }

    @Test func noObservatoryTableKeepsStandard() throws {
        #expect(try parse("").observatory.catalog == .standard)
    }

    @Test func overrideOneRateOfKnownModel() throws {
        let config = try parse(
            """
            [observatory.models."claude-opus-5-5"]
            output = 30.0
            """)

        #expect(config.observatory.catalog.pricing(for: opus)?.output == 30)
        #expect(config.observatory.catalog.pricing(for: opus)?.input == 4)
    }

    @Test func newModelWithAllKeys() throws {
        let config = try parse(
            """
            [observatory.models."claude-next-1"]
            context = 500000
            input = 1
            output = 2
            cache_read = 0.1
            cache_write_5m = 1.25
            cache_write_1h = 2
            """)

        #expect(
            config.observatory.catalog.pricing(for: next)
                == ModelPricing(
                    contextWindow: 500_000, input: 1, output: 2, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2))
    }

    @Test func newModelMissingKeysFailsWithLine() {
        let error = error(
            parsing: """
                [observatory.models."claude-next-1"]
                input = 1
                output = 2
                """)

        #expect(error?.reason == "faltan claves: context, cache_read, cache_write_5m, cache_write_1h")
        #expect(error?.line == 1)
    }

    @Test func negativeRateFails() {
        let error = error(
            parsing: """
                [observatory.models."claude-opus-5-5"]

                input = -1
                """)

        #expect(error?.reason == "debe ser ≥ 0")
        #expect(error?.key == "input")
        #expect(error?.line == 3)
    }

    @Test func nonIntegerContextFails() {
        let error = error(
            parsing: """
                [observatory.models."claude-opus-5-5"]
                context = 1.5
                """)

        #expect(error?.reason == "se esperaba un número entero mayor que 0")
    }

    @Test func unknownKeyInModelFails() {
        let error = error(
            parsing: """
                [observatory.models."claude-opus-5-5"]
                price = 3
                """)

        #expect(error?.reason == "clave desconocida")
        #expect(error?.key == "price")
    }

    @Test func unknownKeyInObservatoryFails() {
        #expect(error(parsing: "[observatory]\nperiod = \"hoy\"")?.reason == "clave desconocida")
    }
}
