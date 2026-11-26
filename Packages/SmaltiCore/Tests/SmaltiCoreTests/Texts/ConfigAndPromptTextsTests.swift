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

/// Review 1 (M2): every problem keeps the exact Spanish the TOML adapter wrote before F7.7, and has its English.
@Suite("Config problems keep their Spanish")
struct ConfigProblemSpanishTests {
    static let cases: [(ConfigProblem, String, String)] = [
        (.syntax, "sintaxis TOML no válida", "invalid TOML syntax"),
        (.unknownTable, "tabla desconocida", "unknown table"),
        (.unknownKey, "clave desconocida", "unknown key"),
        (.unreadableFile(detail: "x"), "no se pudo leer el archivo: x", "the file couldn’t be read: x"),
        (
            .noReadPermission, "no se pudo leer el archivo: sin permiso de lectura",
            "the file couldn’t be read: no read permission"
        ),
        (.notUTF8, "el archivo no está en UTF-8", "the file isn’t UTF-8"),
        (.unwritable(detail: "disco lleno"), "no se pudo escribir: disco lleno", "couldn’t write: disco lleno"),
        (
            .newerNotOverwritten, "es de una versión más nueva de Smalti: no se sobrescribe",
            "it’s from a newer Smalti: it isn’t overwritten"
        ),
        (.expectedTable, "se esperaba una tabla", "expected a table"),
        (.expectedNumber, "se esperaba un número", "expected a number"),
        (.expectedText, "se esperaba un texto", "expected a text"),
        (.expectedFlag, "se esperaba true o false", "expected true or false"),
        (.expectedTextList, "se esperaba una lista de textos", "expected a list of texts"),
        (.expectedVersion, "se esperaba un entero mayor o igual que 1", "expected an integer of at least 1"),
        (
            .expectedIntegerBetween(1, 9), "se esperaba un número entero entre 1 y 9",
            "expected an integer between 1 and 9"
        ),
        (.expectedNumberBetween(6, 72), "se esperaba un número entre 6 y 72", "expected a number between 6 and 72"),
        (.notNegative, "debe ser ≥ 0", "must be ≥ 0"),
        (.expectedPositiveInteger, "se esperaba un número entero mayor que 0", "expected an integer greater than 0"),
        (.missingKeys(["input"]), "faltan claves: input", "missing keys: input"),
        (.expectedANSIIndex, "se esperaba un índice ANSI de 0 a 15", "expected an ANSI index from 0 to 15"),
        (.expectedColor, "se esperaba un color #rrggbb", "expected a #rrggbb color"),
        (
            .expectedFontName(maximumLength: 100),
            "se esperaba un nombre de 1 a 100 caracteres sin comillas, \\ ni caracteres de control",
            "expected a name of 1 to 100 characters without quotes, \\ or control characters"
        ),
        (.expectedOneOf(["a"]), "se esperaba a", "expected a"),
        (
            .unknownTheme(["obsidiana", "niebla"]), "tema desconocido; se esperaba obsidiana o niebla",
            "unknown theme; expected obsidiana or niebla"
        ),
        (
            .unknownLayout(["dwindle", "columns", "master"]),
            "layout desconocido; se esperaba dwindle, columns o master",
            "unknown layout; expected dwindle, columns or master"
        ),
        (.unknownModule("weather"), "módulo desconocido: weather", "unknown module: weather"),
        (.repeatedModule("time"), "módulo repetido: time", "repeated module: time"),
        (.expectedShellCommand, "se esperaba un comando o \"login\"", "expected a command or \"login\""),
        (.expectedCommandID, "se esperaba un id de comando o \"none\"", "expected a command id or \"none\""),
        (
            .unknownCommand, "comando desconocido; se esperaba un id de comando o \"none\"",
            "unknown command; expected a command id or \"none\""
        ),
        (
            .repeatedShortcut(first: "cmd+j"), "atajo repetido; ya aparece como cmd+j",
            "repeated shortcut; it already appears as cmd+j"
        ),
        (.invalidChord(.unknownModifier("hyper")), "modificador desconocido: hyper", "unknown modifier: hyper"),
        (.invalidChord(.unknownKey("foo")), "tecla desconocida: foo", "unknown key: foo"),
        (.invalidChord(.duplicateModifier("cmd")), "modificador repetido: cmd", "repeated modifier: cmd"),
        (.invalidChord(.missingModifier("t")), "falta un modificador (⌘, ⌃ o ⌥)", "a modifier is missing (⌘, ⌃ or ⌥)"),
        (
            .invalidChord(.missingKey("cmd+")), "falta la tecla; el + se escribe plus",
            "the key is missing; write + as plus"
        ),
        (
            .invalidChord(.shiftOnSymbol("shift+cmd+1")),
            "⇧ no cuenta con números ni símbolos: escribe el carácter (cmd+? en vez de shift+cmd+/)",
            "⇧ doesn’t count with numbers or symbols: write the character (cmd+? instead of shift+cmd+/)"
        ),
        (.reservedOption, "⌥ sin ⌘ ni ⌃ queda reservado para escribir", "⌥ without ⌘ or ⌃ is reserved for typing"),
    ]

    @Test func everyProblemInBothLanguages() {
        for (problem, spanish, english) in Self.cases {
            #expect(ConfigTexts.spanish.describe(problem) == spanish)
            #expect(ConfigTexts.english.describe(problem) == english)
        }
    }
}
