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
        CopyTimelineItem(
            sources: TranscriptSources(sessions: [transcripts], projects: []), policy: policy, texts: .spanish)
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

        #expect(copied?.text == whole)
        #expect(copied?.byteCount == 6_000)
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

        #expect(try await copy.copy(id, in: timeline, harness: .claude, part: .content)?.text == "Exit code 127 whole")
        #expect(try await copy.copy(id, in: timeline, harness: .claude, part: .call)?.text == "{\"command\":\"ls\"}")
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

        #expect(copied?.text == "{\"command\":\"sleep\"}")
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

        #expect(copied?.text == "«hola»")
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

    /// Review 1 (I2, M13): an image and a compaction are described, not read from the disk, the same for every harness.
    @Test func imagesAndCompactionsAreDescribed() async throws {
        let image = F.entry(
            .image(
                ImageNote(
                    mediaType: "image/png", byteCount: 186_000,
                    location: F.excerpt("", offset: 5, field: .image).location)))
        let compaction = F.entry(
            .compaction(
                CompactionNote(preTokens: 168_000, postTokens: 22_400, location: F.excerpt("", offset: 6).location)))
        let timeline = Timeline().appending([F.prompt("p", at: 1), image, compaction])
        let copy = make(FakeSessionTranscripts(harness: .codex))
        let items = try #require(timeline.turns.first?.items)

        let copiedImage = try await copy.copy(items[1].id, in: timeline, harness: .codex, part: .content)
        let copiedCompaction = try await copy.copy(items[2].id, in: timeline, harness: .codex, part: .content)

        #expect(copiedImage?.text == "Imagen adjunta · image/png · 186 KB")
        #expect(copiedCompaction?.text == "Conversación compactada · 168k → 22k tokens")
    }

    /// Review 1 (M12): ⇧⌘C copies a call or nothing, never another text.
    @Test func copyingTheCallOfSomethingWithoutCallCopiesNothing() async throws {
        let timeline = Timeline().appending([F.prompt("p", at: 1), F.result("ghost", "out", at: 2)])
        let copy = make(FakeSessionTranscripts(harness: .claude))
        let items = try #require(timeline.turns.first?.items)

        #expect(try await copy.copy(items[0].id, in: timeline, harness: .claude, part: .call) == nil)
        #expect(try await copy.copy(items[1].id, in: timeline, harness: .claude, part: .call) == nil)
    }
}
