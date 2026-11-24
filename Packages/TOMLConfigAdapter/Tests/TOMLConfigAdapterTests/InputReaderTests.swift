import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

@Suite("Input settings in the TOML")
struct InputReaderTests {
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

    @Test func noInputTableKeepsStandard() throws {
        #expect(try parse("").input == .standard)
    }

    @Test func inputTableReadsAllKeys() throws {
        let config = try parse(
            """
            [input]
            enabled = true
            predictions = false
            completions = false
            history_limit = 5000
            generator_timeout_ms = 250
            """)

        #expect(config.input.isEnabled)
        #expect(!config.input.hasPredictions)
        #expect(!config.input.hasCompletions)
        #expect(config.input.historyLimit == 5_000)
        #expect(config.input.generatorTimeout == .milliseconds(250))
    }

    @Test func highlightingDefaultsTrue() throws {
        #expect(try parse("[input]\n").input.isHighlighting)
    }

    @Test func highlightingFalseRead() throws {
        #expect(try !parse("[input]\nhighlighting = false\n").input.isHighlighting)
    }

    @Test func highlightingNotBoolIsTypedError() {
        #expect(error(parsing: "[input]\nhighlighting = 1\n")?.key == "highlighting")
    }

    @Test func inputTableUnknownKeyThrowsWithLine() {
        let error = error(parsing: "[input]\nenabled = true\nghost = 1\n")

        #expect(error?.key == "ghost")
        #expect(error?.line == 3)
    }

    @Test func historyLimitOutOfRangeThrows() {
        #expect(error(parsing: "[input]\nhistory_limit = 0\n")?.key == "history_limit")
        #expect(error(parsing: "[input]\nhistory_limit = 1000001\n")?.key == "history_limit")
    }

    @Test func generatorTimeoutOutOfRangeThrows() {
        #expect(error(parsing: "[input]\ngenerator_timeout_ms = 99\n")?.key == "generator_timeout_ms")
    }

    @Test func nonBooleanFlagThrows() {
        #expect(error(parsing: "[input]\nenabled = \"yes\"\n")?.key == "enabled")
    }
}
