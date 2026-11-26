import SmaltiCore
import SmaltiCoreTestSupport
import Testing

private struct Inner: Sendable {
    let title: String
}

private struct SampleTexts: Sendable {
    let close: String
    let approve: TextTemplate
    let panes: PluralText
    let titles: [Int: String]
    let inner: Inner
}

@Suite("TextCatalogAudit")
struct TextCatalogAuditTests {
    private let spanish = SampleTexts(
        close: "Cerrar", approve: "Aprobar “{quote}”",
        panes: PluralText(one: "{count} panel", other: "{count} paneles"),
        titles: [1: "Uno"], inner: Inner(title: "Título"))
    private let english = SampleTexts(
        close: "Close", approve: "Approve “{quote}”", panes: PluralText(one: "{count} pane", other: "{count} panes"),
        titles: [1: "One"], inner: Inner(title: "Title"))

    @Test func cleanCatalogsHaveNoProblems() {
        #expect(TextCatalogAudit.problems(spanish: spanish, english: english).isEmpty)
    }

    @Test func emptyFieldIsAProblem() {
        let empty = SampleTexts(
            close: "", approve: english.approve, panes: english.panes, titles: english.titles, inner: english.inner)

        #expect(TextCatalogAudit.problems(spanish: spanish, english: empty) == ["close: empty in English"])
    }

    @Test func differentPlaceholdersAreAProblem() {
        let wrong = SampleTexts(
            close: "Close", approve: "Approve “{command}”", panes: english.panes, titles: english.titles,
            inner: english.inner)

        #expect(
            TextCatalogAudit.problems(spanish: spanish, english: wrong) == [
                "approve: placeholders differ (es: quote; en: command)"
            ])
    }

    @Test func pluralFormsAreChecked() {
        let wrong = SampleTexts(
            close: "Close", approve: english.approve, panes: PluralText(one: "one pane", other: "{count} panes"),
            titles: english.titles, inner: english.inner)

        #expect(
            TextCatalogAudit.problems(spanish: spanish, english: wrong) == [
                "panes.one: placeholders differ (es: count; en: )"
            ])
    }

    @Test func dictionaryKeysMustMatch() {
        let wrong = SampleTexts(
            close: "Close", approve: english.approve, panes: english.panes, titles: [2: "Two"], inner: english.inner)

        #expect(TextCatalogAudit.problems(spanish: spanish, english: wrong) == ["titles: keys differ"])
    }

    @Test func spanishLeftInEnglishIsAProblem() {
        let leaked = SampleTexts(
            close: "Close", approve: english.approve, panes: english.panes, titles: [1: "Abrir la ventana"],
            inner: Inner(title: "Título"))

        #expect(
            TextCatalogAudit.problems(spanish: spanish, english: leaked) == [
                "titles[1]: looks Spanish in English (“Abrir la ventana”)",
                "inner.title: looks Spanish in English (“Título”)",
            ])
    }

    @Test func allowedWordsAreNotSpanish() {
        let named = SampleTexts(
            close: "Close", approve: english.approve, panes: english.panes, titles: english.titles,
            inner: Inner(title: "Ámbar"))

        #expect(TextCatalogAudit.problems(spanish: spanish, english: named, allowed: ["Ámbar"]).isEmpty)
    }

    @Test(arguments: ["hace 3h", "línea 42", "¿Cerrar?", "Panel nuevo", "sin entrada"])
    func detectorFlagsSpanish(text: String) {
        #expect(SpanishMarkers.looksSpanish(text))
    }

    @Test(arguments: ["3h ago", "Line 42", "Close window?", "New pane", "dwindle", "⌘K", "Claude Code", "Smalti"])
    func detectorLeavesEnglishAlone(text: String) {
        #expect(!SpanishMarkers.looksSpanish(text))
    }
}

/// Review 1 (M3): a list with a missing line in one language is reported.
@Suite("TextCatalogAudit lists")
struct TextCatalogAuditListTests {
    private struct Lines: Sendable {
        let weekdays: [String]
    }

    @Test func listsOfDifferentLengthAreAProblem() {
        let problems = TextCatalogAudit.problems(
            spanish: Lines(weekdays: ["lun", "mar"]), english: Lines(weekdays: ["Mon"]))

        #expect(problems == ["weekdays: count differs (es: 2; en: 1)"])
    }
}
