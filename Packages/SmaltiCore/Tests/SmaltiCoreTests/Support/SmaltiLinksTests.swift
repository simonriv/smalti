import SmaltiCore
import Testing

/// F7.6: the web's pages the app links to, in Spanish while the interface is (F7.7 makes them follow the language).
@Suite("SmaltiLinks")
struct SmaltiLinksTests {
    @Test func documentation() {
        #expect(SmaltiLinks.documentation.absoluteString == "https://smalti.sh/es/docs")
    }

    @Test func support() {
        #expect(SmaltiLinks.support.absoluteString == "https://smalti.sh/es#apoyar")
    }
}
