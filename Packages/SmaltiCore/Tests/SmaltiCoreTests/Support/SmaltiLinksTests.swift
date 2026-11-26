import Foundation
import SmaltiCore
import Testing

@Suite("SmaltiLinks")
struct SmaltiLinksTests {
    @Test func englishLinksLiveAtTheRoot() {
        #expect(SmaltiLinks.documentation(for: .english).absoluteString == "https://smalti.sh/docs")
        #expect(SmaltiLinks.support(for: .english).absoluteString == "https://smalti.sh/#support")
        #expect(SmaltiLinks.privacy(for: .english).absoluteString == "https://smalti.sh/privacy")
        #expect(
            SmaltiLinks.releaseNotes(version: "0.7.7", for: .english).absoluteString
                == "https://smalti.sh/changelog#v0.7.7")
    }

    @Test func spanishLinksLiveUnderES() {
        #expect(SmaltiLinks.documentation(for: .spanish).absoluteString == "https://smalti.sh/es/docs")
        #expect(SmaltiLinks.support(for: .spanish).absoluteString == "https://smalti.sh/es#apoyar")
        #expect(SmaltiLinks.privacy(for: .spanish).absoluteString == "https://smalti.sh/es/privacy")
        #expect(
            SmaltiLinks.releaseNotes(version: "0.7.7", for: .spanish).absoluteString
                == "https://smalti.sh/es/changelog#v0.7.7")
    }
}

/// Review 1 (M6): a version from outside never crashes the link; it is escaped.
@Suite("SmaltiLinks release notes")
struct SmaltiLinksReleaseNotesTests {
    @Test func oddVersionIsEscaped() {
        #expect(
            SmaltiLinks.releaseNotes(version: "0.7 beta", for: .english).absoluteString
                == "https://smalti.sh/changelog#v0.7%20beta")
    }
}
