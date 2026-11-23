import Testing

@testable import TOMLConfigAdapter

@Suite("TOMLKeyLocator")
struct TOMLKeyLocatorTests {
    @Test func findsKeyInsideItsTable() {
        let text = "[tiling]\ngap = 1\n[appearance]\n# gap = 2\ngap = 3\n"

        let line = TOMLKeyLocator.line(of: "gap", inTable: "appearance", text: text)

        #expect(line == 5)
    }

    @Test func findsTopLevelKeyBeforeAnyTable() {
        let line = TOMLKeyLocator.line(of: "theme", inTable: "", text: "theme = 1\n[appearance]\ntheme = 2")

        #expect(line == 1)
    }

    @Test func findsQuotedKeyThatContainsEquals() {
        let text = "[keys]  # atajos\n\"cmd+k\" = \"palette.open\"\n  \"shift+cmd+=\"= \"panes.equalize\""

        let line = TOMLKeyLocator.line(of: "shift+cmd+=", inTable: "keys", text: text)

        #expect(line == 3)
    }

    @Test func findsLiteralQuotedKey() {
        let line = TOMLKeyLocator.line(of: "cmd+k", inTable: "keys", text: "[keys]\n'cmd+k' = 'palette.open'")

        #expect(line == 2)
    }

    @Test func findsTableHeaderAsAKeyOfItsParent() {
        let text = "[appearance]\n[colors]\n[appearance.extra]\n"

        #expect(TOMLKeyLocator.line(of: "colors", inTable: "", text: text) == 2)
        #expect(TOMLKeyLocator.line(of: "extra", inTable: "appearance", text: text) == 3)
    }

    @Test func toleratesWindowsLineEndings() {
        let line = TOMLKeyLocator.line(of: "blur", inTable: "appearance", text: "[appearance]\r\nblur = 1\r\n")

        #expect(line == 2)
    }

    @Test func missingKeyHasNoLine() {
        let line = TOMLKeyLocator.line(of: "blur", inTable: "appearance", text: "[appearance]\nblurry = 1\n")

        #expect(line == nil)
    }
}
