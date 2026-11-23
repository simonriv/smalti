import SmaltiCore
import Testing

@Suite("LayoutName")
struct LayoutNameTests {
    @Test func layoutNameTrimsSpaces() throws {
        #expect(try LayoutName("  solen-dev ").rawValue == "solen-dev")
    }

    @Test(arguments: ["", "   ", "a/b", "a:b", ".oculto", String(repeating: "x", count: 61)])
    func layoutNameRejectsInvalidNames(raw: String) {
        #expect(throws: LayoutNameError.self) { try LayoutName(raw) }
    }

    @Test func sixtyCharactersAreAllowed() throws {
        #expect(try LayoutName(String(repeating: "x", count: 60)).rawValue.count == 60)
    }

    @Test func spacesAndAccentsAreAllowed() throws {
        #expect(try LayoutName("rizaria completo ñ").rawValue == "rizaria completo ñ")
    }

    @Test(arguments: ["solen\ndev", "a\u{0}b", "tab\there"])
    func layoutNameRejectsControlCharacters(raw: String) {
        #expect(throws: LayoutNameError.self) { try LayoutName(raw) }
    }

    @Test func layoutNameTrimsTrailingNewline() throws {
        #expect(try LayoutName("solen-dev\n").rawValue == "solen-dev")
    }
}
