import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

/// Spec F7: `[extras] otlp` in `config.toml`, on by default.
@Suite("Extras settings in the TOML")
struct ExtrasReaderTests {
    private func parse(_ text: String) throws(ConfigError) -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: "config.toml")
    }

    @Test func extrasDefaultsToOtlpOn() throws {
        #expect(try parse("").extras == ExtrasSettings(otlp: true))
        #expect(ExtrasSettings.standard.otlp)
    }

    @Test func extrasReadsFalse() throws {
        #expect(try parse("[extras]\notlp = false\n").extras.otlp == false)
    }

    @Test func extrasRejectsNonBoolean() {
        do {
            _ = try parse("[extras]\notlp = \"sí\"\n")
            Issue.record("a non-boolean otlp was accepted")
        } catch {
            #expect(error.line == 2)
            #expect(error.key == "otlp")
        }
    }

    @Test func extrasRejectsUnknownKey() {
        do {
            _ = try parse("[extras]\notlp = true\nlayouts = true\n")
            Issue.record("an unknown key was accepted")
        } catch {
            #expect(error.line == 3)
        }
    }

    @Test func extrasInThemeTomlIsRejected() {
        #expect(throws: ConfigError.self) {
            try TOMLConfigParser.parseTheme("[extras]\notlp = false\n", file: "theme.toml", over: .defaults)
        }
    }
}
