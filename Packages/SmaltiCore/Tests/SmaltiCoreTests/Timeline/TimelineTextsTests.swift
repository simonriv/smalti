import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("TimelineTexts")
struct TimelineTextsTests {
    @Test func bothLanguagesAreComplete() {
        #expect(TimelineTexts.spanish != TimelineTexts.english)
        #expect(TextCatalogAudit.problems(spanish: TimelineTexts.spanish, english: TimelineTexts.english).isEmpty)
    }

    @Test func englishFollowsTheGlossary() {
        let english = TimelineTexts.english

        #expect(english.you == "You")
        #expect(english.done == "done")
        #expect(english.compacted == "Conversation compacted")
        #expect(english.noAgentTitle == "This pane has no agent")
    }

    @Test(arguments: [
        (999, "999 B"), (1_000, "1 KB"), (1_499, "1 KB"), (1_500, "2 KB"), (186_000, "186 KB"), (1_000_000, "1,0 MB"),
        (1_234_567, "1,2 MB"), (1_250_000, "1,3 MB"), (61_000_000, "61,0 MB"),
    ])
    func sizesInFinderUnits(bytes: Int, text: String) {
        #expect(TimelineTexts.spanish.size(bytes) == text)
    }

    @Test func englishSizesUseAPoint() {
        #expect(TimelineTexts.english.size(1_234_567) == "1.2 MB")
    }
}
