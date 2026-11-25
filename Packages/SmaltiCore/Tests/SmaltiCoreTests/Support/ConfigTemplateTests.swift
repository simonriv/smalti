import SmaltiCore
import Testing

@Suite("ConfigTemplate")
struct ConfigTemplateTests {
    private let text = ConfigTemplate.text(defaults: .defaults)

    @Test func everyValueLineIsCommented() {
        let values = text.split(separator: "\n").filter { $0.contains(" = ") }

        #expect(!values.isEmpty)
        #expect(values.allSatisfy { $0.hasPrefix("# ") || $0 == "version = 1" })
    }

    /// F7.6: the only uncommented value, so an older Smalti knows the file is newer.
    @Test func templateStartsTheFileWithItsVersion() {
        let firstValue = text.split(separator: "\n").first { !$0.hasPrefix("#") && !$0.isEmpty }

        #expect(firstValue == "version = 1")
    }

    @Test(arguments: [
        "[appearance]", "# font_size = 13", "# glass_opacity = 0.62", "# accent = \"#7aa2f7\"", "[tiling]",
        "# default_layout = \"dwindle\"", "[shell]", "# command = \"login\"", "[input]", "# history_limit = 100000",
        "[window]", "# confirm_close = true", "[preview]", "# hover = true", "[keys]",
    ])
    func templateNamesEveryTableAndDefault(_ line: String) {
        #expect(text.split(separator: "\n").contains { $0 == line })
    }

    /// Mutation (F4.5): seconds and the fraction both count in the milliseconds.
    @Test func generatorTimeoutIsWrittenInMilliseconds() {
        var config = SmaltiConfig.defaults
        config.input.generatorTimeout = .milliseconds(2_500)

        #expect(ConfigTemplate.text(defaults: config).contains("# generator_timeout_ms = 2500\n"))
    }

    /// Mutation (F4.5): prose that happens to hold " = " stays a comment.
    @Test func proseWithAnEqualsSignStaysCommented() {
        #expect(ConfigTemplate.uncommented("# Ejemplo = algo") == "# Ejemplo = algo")
    }

    @Test func templateExplainsHowKeysReplaceDefaults() {
        #expect(text.contains("reemplazan"))
        #expect(text.contains("\"none\""))
    }

    @Test func templateShowsTheKeysSyntaxAndAnObservatoryExample() {
        #expect(text.contains("# \"cmd+t\" = \"pane.new\""))
        #expect(text.contains("[observatory.models."))
    }

    @Test func stringsWithQuotesAndBackslashesAreEscaped() {
        var config = SmaltiConfig.defaults
        config.shell = .custom(#"/bin/zsh -c "echo \ hi""#)

        #expect(ConfigTemplate.text(defaults: config).contains(#"# command = "/bin/zsh -c \"echo \\ hi\"""#))
    }

    @Test func uncommentingTurnsValuesIntoTOML() {
        #expect(ConfigTemplate.uncommented("# a = 1\n\n# b = 2") == "a = 1\n\nb = 2")
        let uncommented = ConfigTemplate.uncommented(text)

        #expect(uncommented.contains("\nfont_size = 13\n"))
        #expect(uncommented.contains("# Configuración de Smalti"))
    }
}
