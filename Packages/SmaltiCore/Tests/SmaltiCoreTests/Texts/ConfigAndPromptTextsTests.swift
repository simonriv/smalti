import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Config, prompt and appearance texts")
struct ConfigAndPromptTextsTests {
    @Test func catalogsHaveBothLanguages() {
        #expect(
            TextCatalogAudit.problems(
                spanish: ConfigTexts.spanish, english: ConfigTexts.english,
                allowed: ["option_as_meta", "plus", "login", "none"]
            ).isEmpty)
        #expect(
            TextCatalogAudit.problems(
                spanish: PromptCopy.spanish, english: PromptCopy.english, allowed: ["Node, Bun, Python, Go"]
            ).isEmpty)
        #expect(TextCatalogAudit.problems(spanish: AppearanceCopy.spanish, english: AppearanceCopy.english).isEmpty)
    }

    @Test(arguments: [
        (ConfigProblem.expectedNumber, "se esperaba un número", "expected a number"),
        (
            .expectedNumberBetween(0.3, 0.95), "se esperaba un número entre 0,3 y 0,95",
            "expected a number between 0.3 and 0.95"
        ),
        (
            .expectedIntegerBetween(1, 10), "se esperaba un número entero entre 1 y 10",
            "expected an integer between 1 and 10"
        ),
        (
            .expectedOneOf(["hidden", "hover", "visible"]), "se esperaba hidden, hover o visible",
            "expected hidden, hover or visible"
        ),
        (.reservedOption, "⌥ sin ⌘ ni ⌃ queda reservado para escribir", "⌥ without ⌘ or ⌃ is reserved for typing"),
        (
            .invalidChord(.missingKey("cmd+")), "falta la tecla; el + se escribe plus",
            "the key is missing; write + as plus"
        ),
        (.missingKeys(["input", "output"]), "faltan claves: input, output", "missing keys: input, output"),
        (.syntax, "sintaxis TOML no válida", "invalid TOML syntax"),
    ])
    func problemsInBothLanguages(problem: ConfigProblem, spanish: String, english: String) {
        #expect(ConfigTexts.spanish.describe(problem) == spanish)
        #expect(ConfigTexts.english.describe(problem) == english)
    }

    @Test func errorSummaryNamesFileLineAndKey() {
        let error = ConfigError(file: "config.toml", line: 12, key: "font_size", problem: .expectedNumber)

        #expect(error.summary(.english) == "config.toml:12 · font_size: expected a number")
    }

    @Test func optionAsMetaDefaultsToAuto() {
        #expect(SmaltiConfig.defaults.optionAsMeta == .auto)
        #expect(OptionAsMeta.allCases.map(\.rawValue) == ["auto", "never", "left", "right", "always"])
    }

    @Test func templateInEnglishHasNoSpanish() {
        let text = ConfigTemplate.text(defaults: .defaults, texts: ConfigTexts.english.template)
        let comments = text.split(separator: "\n").filter { $0.hasPrefix("# ") && !$0.contains(" = ") }

        #expect(comments.filter { SpanishMarkers.looksSpanish(String($0)) }.isEmpty)
        #expect(
            text.contains(
                "[keyboard]\n# ⌥ as Meta: auto (by keyboard layout), never, left, right or always.\n# option_as_meta = \"auto\""
            ))
    }

    @Test func previewsUseNeutralProjects() {
        let copy = PromptCopy.english
        let titles = PreviewSituation.allCases.map { $0.title(copy) }

        #expect(titles == ["Regular folder", "Node project with git", "After an error, with an active agent"])
    }

    @Test func themeNamesInEnglish() {
        #expect(ThemeID.allCases.map { $0.displayName(.english) } == ["Obsidian", "Mist", "Night Amber", "Forest"])
    }

    @Test func appearanceTextsInEnglish() {
        #expect(AppearanceTexts.adjusted(3, copy: .english) == "Adjusted for legibility: 3 colors")
        #expect(AppearanceTexts.opacity(chosen: 0.62, underText: 0.66, copy: .english) == "62% · 66% under the text")
    }

    @Test func feedbackTitleFollowsTheLanguage() {
        let build = BuildInfo(version: "0.7.7", commit: "abc", macOS: "27.2", chip: "Apple M4")

        #expect(
            FeedbackReport.issueURL(kind: .bug, build: build, texts: .english).absoluteString.contains(
                "title=Bug%3A%20"))
        #expect(
            FeedbackReport.issueURL(kind: .bug, build: build, texts: .spanish).absoluteString.contains(
                "title=Fallo%3A%20"))
    }
}
