import SmaltiCore
import Testing

@Suite("ConfigTemplate")
struct ConfigTemplateTests {
    private let text = ConfigTemplate.text(defaults: .defaults)

    @Test func everyValueLineIsCommented() {
        let values = text.split(separator: "\n").filter { $0.contains(" = ") }

        #expect(!values.isEmpty)
        #expect(values.allSatisfy { $0.hasPrefix("# ") })
    }

    @Test(arguments: [
        "[appearance]", "# font_size = 13", "# glass_opacity = 0.62", "# accent = \"#7aa2f7\"", "[tiling]",
        "# default_layout = \"dwindle\"", "[shell]", "# command = \"login\"", "[input]", "# history_limit = 100000",
        "[window]", "# confirm_close = true", "[keys]",
    ])
    func templateNamesEveryTableAndDefault(_ line: String) {
        #expect(text.split(separator: "\n").contains { $0 == line })
    }

    @Test func templateExplainsHowKeysReplaceDefaults() {
        #expect(text.contains("reemplazan"))
        #expect(text.contains("\"none\""))
    }

    @Test func uncommentingTurnsValuesIntoTOML() {
        let uncommented = ConfigTemplate.uncommented(text)

        #expect(uncommented.contains("\nfont_size = 13\n"))
        #expect(uncommented.contains("# Configuración de Smalti"))
    }
}
