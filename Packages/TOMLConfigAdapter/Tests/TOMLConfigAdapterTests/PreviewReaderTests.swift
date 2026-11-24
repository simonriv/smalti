import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

/// Spec F5.5: `[preview] hover` in `config.toml`; it is not appearance, so `theme.toml` does not take it.
@Suite("Preview settings in the TOML")
struct PreviewReaderTests {
    private func parse(_ text: String) throws(ConfigError) -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: "config.toml")
    }

    @Test func missingSectionUsesDefault() throws {
        #expect(try parse("").preview == .standard)
    }

    @Test func hoverFalseIsRead() throws {
        #expect(try parse("[preview]\nhover = false\n").preview.hover == false)
    }

    @Test func invalidHoverNamesLine() {
        #expect(throws: ConfigError.self) { try parse("[preview]\nhover = \"sí\"\n") }
        do {
            _ = try parse("[preview]\nhover = \"sí\"\n")
        } catch {
            #expect(error.line == 2)
            #expect(error.key == "hover")
        }
    }

    @Test func unknownKeyNamesLine() {
        do {
            _ = try parse("[preview]\nhover = true\nsize = 3\n")
            Issue.record("an unknown key was accepted")
        } catch {
            #expect(error.line == 3)
        }
    }

    @Test func previewInThemeTomlIsRejected() {
        #expect(throws: ConfigError.self) {
            try TOMLConfigParser.parseTheme("[preview]\nhover = false\n", file: "theme.toml", over: .defaults)
        }
    }
}
