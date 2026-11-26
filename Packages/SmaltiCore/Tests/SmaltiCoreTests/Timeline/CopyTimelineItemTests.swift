import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("CopyTimelineItem")
struct CopyTimelineItemTests {
    private typealias F = TimelineFixtures

    private func make(_ transcripts: FakeSessionTranscripts, policy: any TranscriptTextPolicy = VerbatimText())
        -> CopyTimelineItem
    {
        CopyTimelineItem(sources: TranscriptSources(sessions: [transcripts], projects: []), policy: policy)
    }

    @Test func aCutPromptIsCopiedWhole() async throws {
        let whole = String(repeating: "ñ", count: 3_000)
        let entry = F.prompt(whole, at: 7)
        let timeline = Timeline().appending([entry])
        let transcripts = FakeSessionTranscripts(harness: .claude)
        guard case .prompt(let text) = entry.kind else { return }
        await transcripts.setFullText(whole, at: text.location)
        let id = try #require(timeline.turns.first?.items.first?.id)

        let copied = try await make(transcripts).copy(id, in: timeline, harness: .claude, part: .content)

        #expect(copied.text == whole)
        #expect(copied.byteCount == 6_000)
    }

    @Test func aToolCopiesItsOutputOrItsCall() async throws {
        let timeline = Timeline().appending(F.workB)
        let id = TimelineItemID(rawValue: "tool:t1")
        guard case .tool(let tool) = timeline.item(id), let call = tool.call, let output = tool.result?.output else {
            Issue.record("expected tool t1 with call and output")
            return
        }
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.setFullText("Exit code 127 whole", at: output.location)
        await transcripts.setFullText("{\"command\":\"ls\"}", at: call.location)
        let copy = make(transcripts)

        #expect(try await copy.copy(id, in: timeline, harness: .claude, part: .content).text == "Exit code 127 whole")
        #expect(try await copy.copy(id, in: timeline, harness: .claude, part: .call).text == "{\"command\":\"ls\"}")
    }

    @Test func aWorkingToolCopiesItsCall() async throws {
        let timeline = Timeline().appending([F.prompt("p", at: 1), F.call("x", "Bash", ["command": "sleep"], at: 2)])
        guard case .tool(let tool) = timeline.item(TimelineItemID(rawValue: "tool:x")), let call = tool.call else {
            Issue.record("expected tool x")
            return
        }
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.setFullText("{\"command\":\"sleep\"}", at: call.location)

        let copied = try await make(transcripts).copy(
            TimelineItemID(rawValue: "tool:x"), in: timeline, harness: .claude, part: .content)

        #expect(copied.text == "{\"command\":\"sleep\"}")
    }

    @Test func copiesPassThePolicyAsCopies() async throws {
        let spy = SpyPolicy()
        let entry = F.reply("hola", at: 3)
        let timeline = Timeline().appending([entry])
        let transcripts = FakeSessionTranscripts(harness: .claude)
        guard case .reply(let text) = entry.kind else { return }
        await transcripts.setFullText("hola", at: text.location)

        let copied = try await make(transcripts, policy: spy).copy(
            #require(timeline.turns.first?.items.first?.id), in: timeline, harness: .claude, part: .content)

        #expect(copied.text == "«hola»")
        #expect(spy.seen.map(\.1) == [.copy])
    }

    @Test func aFileThatChangedFails() async throws {
        let entry = F.reply("hola", at: 3)
        let timeline = Timeline().appending([entry])

        await #expect(throws: TranscriptReadError.self) {
            try await make(FakeSessionTranscripts(harness: .claude)).copy(
                #require(timeline.turns.first?.items.first?.id), in: timeline, harness: .claude, part: .content)
        }
    }
}
