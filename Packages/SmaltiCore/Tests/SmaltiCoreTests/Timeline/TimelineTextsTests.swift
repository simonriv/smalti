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
}
