import SmaltiCore
import Testing

@Suite("TextTemplate")
struct TextTemplateTests {
    private let approve: TextTemplate = "Aprobar “{quote}” en {workspace}"

    @Test func fillsEveryPlaceholder() {
        #expect(approve(["quote": "ls", "workspace": "web"]) == "Aprobar “ls” en web")
    }

    @Test func placeholderNamesTakeDigitsAndUnderscores() {
        let template: TextTemplate = "{first_name} {n2}"

        #expect(template(["first_name": "Ada", "n2": "2"]) == "Ada 2")
    }

    @Test func listsItsPlaceholders() {
        #expect(approve.placeholders == ["quote", "workspace"])
    }

    @Test func textWithoutPlaceholdersStaysTheSame() {
        let plain: TextTemplate = "Nueva ventana"

        #expect(plain([:]) == "Nueva ventana")
        #expect(plain.placeholders.isEmpty)
    }

    @Test func valueWithBracesIsNotReinterpreted() {
        #expect(approve(["quote": "{workspace}", "workspace": "web"]) == "Aprobar “{workspace}” en web")
    }

    @Test func missingValueLeavesThePlaceholder() {
        #expect(approve(["quote": "ls"]) == "Aprobar “ls” en {workspace}")
    }

    @Test func repeatedPlaceholderIsFilledEverywhere() {
        let twice: TextTemplate = "{n} de {n}"

        #expect(twice(["n": "3"]) == "3 de 3")
        #expect(twice.placeholders == ["n"])
    }

    @Test func lonelyBracesAreKept() {
        let braces: TextTemplate = "{ x } y {}"

        #expect(braces([:]) == "{ x } y {}")
        #expect(braces.placeholders.isEmpty)
    }
}

@Suite("PluralText")
struct PluralTextTests {
    private let panes = PluralText(one: "{count} panel", other: "{count} paneles")

    @Test func oneUsesTheSingular() {
        #expect(panes(1) == "1 panel")
    }

    @Test(arguments: [0, 2, 9])
    func otherCountsUseThePlural(count: Int) {
        #expect(panes(count) == "\(count) paneles")
    }

    @Test func extraValuesFillTheirPlaceholders() {
        let sessions = PluralText(
            one: "retoma {count} sesión de {harness}", other: "retoma {count} sesiones de {harness}")

        #expect(sessions(2, ["harness": "Claude"]) == "retoma 2 sesiones de Claude")
    }
}
