import Foundation
import SmaltiCore
import Testing

/// Records every text that went through it, to prove rows are only built from the policy's output (C11).
final class SpyPolicy: TranscriptTextPolicy, @unchecked Sendable {
    // Unchecked: tests use it from one task.
    private(set) var seen: [(String, TranscriptTextContext)] = []

    func shown(_ text: String, as context: TranscriptTextContext) -> String {
        seen.append((text, context))
        return "«\(text)»"
    }
}

@Suite("TimelineRows")
struct TimelineRowsTests {
    private typealias F = TimelineFixtures
    private let texts = TimelineTexts.spanish

    private func rows(
        _ timeline: Timeline, expanded: Set<TimelineItemID> = [], policy: any TranscriptTextPolicy = VerbatimText()
    )
        -> [TimelineRow]
    {
        TimelineRows.rows(
            timeline, harness: .claude, expanded: expanded, policy: policy, texts: texts, time: { _ in "10:58" })
    }

    @Test func eachItemIsARowWithWhoAndTime() {
        let all = rows(Timeline().appending(F.workB))

        #expect(all.count == 9)
        #expect(all.map(\.kind) == [.prompt, .tool, .tool, .reply, .prompt, .tool, .reply, .prompt, .reply])
        #expect(all[0].who == "Tú")
        #expect(all[3].who == "Claude")
        #expect(all[1].who == "Bash")
        #expect(all[0].time == "10:58")
    }

    /// Mutation: only an expanded tool says it is expanded, and only a cut text says it is cut.
    @Test func rowsSayWhatIsExpandedAndCut() {
        let location = F.excerpt("", offset: 9).location
        let timeline = Timeline().appending(
            F.workB + [F.entry(.image(ImageNote(mediaType: "image/png", byteCount: 1, location: location)))])

        let all = rows(timeline)

        #expect(all.allSatisfy { !$0.isExpanded })
        #expect(all.allSatisfy { !$0.isTruncated })
    }

    @Test func anExpandedOutputKeepsItsBlankLines() throws {
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.call("t", "Bash", [:], at: 2), F.result("t", "uno\n\ndos", at: 3),
        ])

        let tool = try #require(rows(timeline, expanded: [TimelineItemID(rawValue: "tool:t")]).last)

        #expect(tool.expandedText == "uno\n\ndos")
        #expect(tool.moreLines == 0)
    }

    @Test func toolsShowSummaryAndStatus() {
        let all = rows(Timeline().appending(F.workB))

        #expect(all[1].summary == "ls")
        #expect(all[1].status == .failed(exitCode: 127))
        #expect(all[1].statusText == "error · exit 127")
        #expect(all[2].statusText == "listo")
        #expect(all[1].isExpanded == false)
        #expect(all[1].expandedText == nil)
    }

    @Test func anExpandedToolShowsTwelveLinesAndTheRest() throws {
        let output = (1...30).map { "línea \($0)" }.joined(separator: "\n")
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.call("t", "Bash", ["command": "seq 30"], at: 2),
            F.result("t", output, at: 3),
        ])

        let tool = try #require(rows(timeline, expanded: [TimelineItemID(rawValue: "tool:t")]).last)

        #expect(tool.isExpanded)
        #expect(tool.expandedText == (1...12).map { "línea \($0)" }.joined(separator: "\n"))
        #expect(tool.moreLines == 18)
        #expect(tool.expandedLabel == "Salida")
    }

    @Test func aToolWithoutResultExpandsToItsCall() throws {
        let timeline = Timeline().appending([F.prompt("p", at: 1), F.call("t", "Bash", ["command": "sleep 9"], at: 2)])

        let tool = try #require(rows(timeline, expanded: [TimelineItemID(rawValue: "tool:t")]).last)

        #expect(tool.expandedLabel == "Llamada")
        #expect(tool.expandedText == "command=sleep 9")
        #expect(tool.statusText == "trabajando")
        #expect(tool.moreLines == 0)
    }

    @Test func anExpandedAgentShowsItsChildrenOneLevelDeeper() {
        let agent = EntryScope.subagent("a8")
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.call("t", "Agent", ["description": "cuenta"], at: 2),
            F.call("s1", "Bash", ["command": "ls"], at: 4, scope: agent),
            F.entry(.subagentLink(agentID: "a8", toolID: "t")),
        ])

        let closed = rows(timeline)
        let open = rows(timeline, expanded: [TimelineItemID(rawValue: "tool:t")])

        #expect(closed.count == 2)
        #expect(open.count == 3)
        #expect(open.map(\.depth) == [0, 0, 1])
        #expect(open[1].summary == "cuenta")
        #expect(open[1].childCount == 1)
    }

    @Test func aLongPromptIsCutButKnowsItsSize() throws {
        let long = String(repeating: "a", count: 3_000)

        let row = try #require(rows(Timeline().appending([F.prompt(long, at: 1)])).first)

        #expect(row.text.count == ExcerptText.limit)
        #expect(row.isTruncated)
    }

    @Test func everyShownTextGoesThroughThePolicy() {
        let spy = SpyPolicy()
        let timeline = Timeline().appending(F.workB)

        let all = rows(timeline, expanded: [TimelineItemID(rawValue: "tool:t1")], policy: spy)

        #expect(all.allSatisfy { $0.text.isEmpty || $0.text.hasPrefix("«") })
        #expect(all.compactMap(\.expandedText).allSatisfy { $0.hasPrefix("«") })
        #expect(all.compactMap(\.summary).allSatisfy { $0.hasPrefix("«") })
        #expect(spy.seen.allSatisfy { $0.1 == .display })
    }

    @Test func compactionAndImageRowsSayWhatTheyAre() {
        let location = F.excerpt("", offset: 9).location
        let timeline = Timeline().appending([
            F.prompt("p", at: 1),
            F.entry(.image(ImageNote(mediaType: "image/png", byteCount: 186_000, location: location))),
            F.entry(
                .compaction(
                    CompactionNote(preTokens: 168_000, postTokens: 22_400, location: F.excerpt("", offset: 10).location)
                )),
            F.entry(
                .compaction(
                    CompactionNote(preTokens: nil, postTokens: nil, location: F.excerpt("", offset: 11).location))),
        ])

        let all = rows(timeline)

        #expect(all[1].text == "Imagen adjunta · image/png")
        #expect(all[2].text == "Conversación compactada · 168k → 22k tokens")
        #expect(all[3].text == "Conversación compactada")
    }

    @Test func codexRepliesSayCodex() {
        let all = TimelineRows.rows(
            Timeline().appending([F.reply("hola", at: 1)]), harness: .codex, expanded: [], policy: VerbatimText(),
            texts: .english, time: { _ in "" })

        #expect(all[0].who == "Codex")
    }
}
