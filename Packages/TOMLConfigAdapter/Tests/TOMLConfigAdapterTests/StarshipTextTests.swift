import Foundation
import SmaltiCore
import Testing
import TOMLDecoder

import TOMLConfigAdapter

/// Spec F5, C11: `starship.toml` matches the golden file of each template and is valid TOML.
@Suite("starship.toml text")
struct StarshipTextTests {
    private func text(_ template: PromptTemplate) -> String {
        var appearance = AppearanceSettings.obsidian
        appearance.protectLegibility = false
        let preset = StarshipPreset.make(
            from: PromptConfig.standard.applying(template), theme: ThemeCatalog.apply(appearance))
        return StarshipText.render(preset)
    }

    private static let goldenNames: [PromptTemplate: String] = [
        .cleanLine: "starship-clean-line", .singleLine: "starship-single-line", .pills: "starship-pills",
        .symbolOnly: "starship-symbol-only",
    ]

    @Test(arguments: PromptTemplate.allCases)
    func starshipMatchesGolden(_ template: PromptTemplate) throws {
        let name = Self.goldenNames[template] ?? ""
        // `SMALTI_WRITE_GOLDEN=1 swift test …` rewrites the golden files; review the diff before committing.
        if ProcessInfo.processInfo.environment["SMALTI_WRITE_GOLDEN"] == "1" {
            try text(template).write(to: Fixture.url(name), atomically: true, encoding: .utf8)
        }
        let golden = try Fixture.text(name)

        #expect(text(template) == golden)
    }

    @Test(arguments: PromptTemplate.allCases)
    func starshipIsValidTOML(_ template: PromptTemplate) throws {
        let table = try TOMLTable(source: text(template))

        #expect(try table.string(forKey: "format").hasSuffix("$character"))
        #expect(try table.bool(forKey: "add_newline") == false)
    }

    @Test func quotesAndBackslashesAreEscaped() throws {
        var config = PromptConfig.standard
        config.symbol = .dollar
        let preset = StarshipPreset.make(from: config, theme: ThemeCatalog.apply(.obsidian))

        let table = try TOMLTable(source: StarshipText.render(preset))

        #expect(try table.table(forKey: "character").string(forKey: "success_symbol").hasPrefix("[\\$]"))
    }
}
