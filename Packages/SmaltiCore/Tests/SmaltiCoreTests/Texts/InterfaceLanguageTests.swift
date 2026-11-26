import SmaltiCore
import Testing

@Suite("InterfaceLanguage")
struct InterfaceLanguageTests {
    @Test(arguments: [
        (["en-US"], InterfaceLanguage.english), (["es-CO"], .spanish), (["es-419"], .spanish), (["es"], .spanish),
        (["fr"], .english), (["fr-FR", "es-CO"], .spanish), (["fr-FR", "en-GB", "es"], .english), ([], .english),
        (["Base"], .english),
    ])
    func firstEnglishOrSpanishEntryDecides(preferred: [String], expected: InterfaceLanguage) {
        #expect(InterfaceLanguage(preferredLocalizations: preferred) == expected)
    }

    @Test func rawValuesAreTheLanguageCodes() {
        #expect(InterfaceLanguage.english.rawValue == "en")
        #expect(InterfaceLanguage.spanish.rawValue == "es")
    }
}
