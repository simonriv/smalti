import Foundation
import SmaltiCore
import Testing

@Suite("SessionActivity")
struct SessionActivityTests {
    private let opus = ModelID(rawValue: "claude-opus-5-5")
    private let haiku = ModelID(rawValue: "claude-haiku-5-5")
    /// 2026-11-18 10:00:00 UTC, on a quarter-hour boundary.
    private let base = Date(timeIntervalSince1970: 1_795_000_000 - 4_000)

    private func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }

    private func usage(output: Int, input: Int = 10, cacheRead: Int = 0) -> TokenUsage {
        TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite5m: 0, cacheWrite1h: 0)
    }

    private func turn(
        _ id: String, _ seconds: Double, output: Int = 100, model: ModelID? = nil, subagent: Bool = false,
        input: Int = 10
    ) -> TranscriptRecord {
        .assistantTurn(
            AssistantTurn(
                messageID: id, model: model ?? opus, usage: usage(output: output, input: input), at: at(seconds),
                isSubagent: subagent))
    }

    private func fold(_ records: [TranscriptRecord]) -> SessionActivity {
        SessionActivity(sessionID: "s").folding(records)
    }

    private func total(_ activity: SessionActivity) -> TokenUsage {
        activity.buckets.values.flatMap(\.usageByModel.values).reduce(.zero, +)
    }

    @Test func baseIsOnAQuarterHour() {
        #expect(QuarterHour(containing: base).start == base)
    }

    @Test func repeatedMessageCountsOnce() {
        let activity = fold([turn("m1", 0), turn("m1", 1), turn("m1", 2)])

        #expect(total(activity).output == 100)
    }

    @Test func repeatedMessageAcrossFoldsCountsOnce() {
        let first = fold([turn("m1", 0)])

        let second = first.folding([turn("m1", 0), turn("m2", 5)])

        #expect(total(second).output == 200)
    }

    @Test func turnsLandInQuarterHourBuckets() {
        let activity = fold([turn("a", 899), turn("b", 900)])

        #expect(activity.buckets[QuarterHour(containing: at(0))]?.usageByModel[opus]?.output == 100)
        #expect(activity.buckets[QuarterHour(containing: at(900))]?.usageByModel[opus]?.output == 100)
        #expect(activity.buckets.count == 2)
    }

    @Test func usageIsKeptPerModel() {
        let activity = fold([turn("a", 0), turn("b", 1, model: haiku, subagent: true)])

        let bucket = activity.buckets[QuarterHour(containing: at(0))]
        #expect(bucket?.usageByModel[opus]?.output == 100)
        #expect(bucket?.usageByModel[haiku]?.output == 100)
    }

    @Test func subagentAddsTokensButNotModelOrContext() {
        let activity = fold([turn("a", 0, input: 50), turn("b", 1, model: haiku, subagent: true, input: 999)])

        #expect(activity.model == opus)
        #expect(activity.contextTokens == 50)
        #expect(total(activity).input == 1_049)
    }

    @Test func syntheticTurnDoesNotSetModel() {
        let activity = fold([turn("a", 0), turn("b", 1, output: 0, model: .synthetic, input: 0)])

        #expect(activity.model == opus)
        #expect(activity.contextTokens == 10)
    }

    @Test func contextComesFromLastMainTurn() {
        let activity = fold([turn("a", 0, input: 10), turn("b", 1, input: 70)])

        #expect(activity.contextTokens == 70)
    }

    @Test func outputByMinuteKeepsLastSixtyMinutes() {
        let activity = fold([turn("a", 0), turn("b", 61 * 60, output: 7)])

        #expect(activity.outputByMinute.count == 1)
        #expect(activity.outputByMinute.values.first == 7)
    }

    @Test func bucketPeakIsHighestMinute() {
        let activity = fold([turn("a", 0, output: 40), turn("b", 30, output: 50), turn("c", 120, output: 70)])

        let bucket = activity.buckets[QuarterHour(containing: at(0))]
        #expect(bucket?.peakOutput == 90)
        #expect(bucket?.peakMinute == at(0))
    }

    @Test func toolFinishCountsCallAndError() {
        let activity = fold([
            .toolStarted(ToolStart(id: "t1", name: "Bash", input: ["command": "ls"], at: at(0))),
            .toolFinished(ToolFinish(id: "t1", isError: true, exitCode: 1, diff: nil, at: at(2))),
        ])

        let bucket = activity.buckets[QuarterHour(containing: at(0))]
        #expect(bucket?.toolCalls == 1)
        #expect(bucket?.toolErrors == 1)
        #expect(activity.recentTools.first?.outcome == .failed(exitCode: 1))
    }

    @Test func toolFinishInLaterFoldClosesPendingTool() {
        let started = fold([
            .toolStarted(ToolStart(id: "t1", name: "Read", input: ["file_path": "/a/b.swift"], at: at(0)))
        ])

        let finished = started.folding([
            .toolFinished(ToolFinish(id: "t1", isError: false, exitCode: nil, diff: nil, at: at(1)))
        ])

        #expect(finished.recentTools.map(\.summary) == ["b.swift"])
    }

    @Test func orphanToolFinishIsIgnored() {
        let activity = fold([.toolFinished(ToolFinish(id: "x", isError: false, exitCode: nil, diff: nil, at: at(1)))])

        #expect(activity.recentTools.isEmpty)
        #expect(activity.buckets.isEmpty)
    }

    @Test func recentToolsKeepsFiveNewestFirst() {
        let records = (1...6).flatMap { index -> [TranscriptRecord] in
            [
                .toolStarted(
                    ToolStart(id: "t\(index)", name: "Bash", input: ["command": "c\(index)"], at: at(Double(index)))),
                .toolFinished(
                    ToolFinish(id: "t\(index)", isError: false, exitCode: nil, diff: nil, at: at(Double(index)))),
            ]
        }

        let activity = fold(records)

        #expect(activity.recentTools.map(\.summary) == ["c6", "c5", "c4", "c3", "c2"])
    }

    @Test func bashDurationIsFinishMinusStart() {
        let activity = fold([
            .toolStarted(ToolStart(id: "t1", name: "Bash", input: ["command": "make"], at: at(0))),
            .toolFinished(ToolFinish(id: "t1", isError: false, exitCode: nil, diff: nil, at: at(1.8))),
        ])

        guard case .succeeded(let duration) = activity.recentTools.first?.outcome else {
            Issue.record("expected a succeeded tool")
            return
        }
        #expect(abs(duration - 1.8) < 0.000_1)
    }

    @Test func compactionKeepsLatest() {
        let activity = fold([
            .compacted(Compaction(at: at(0), preTokens: 900, postTokens: 100)),
            .compacted(Compaction(at: at(60), preTokens: 800, postTokens: 50)),
        ])

        #expect(activity.lastCompaction == Compaction(at: at(60), preTokens: 800, postTokens: 50))
    }

    @Test func firstAndLastActivityTrackTimestamps() {
        let activity = fold([.sessionInfo(sessionID: "s", cwd: "/w", at: at(5)), turn("a", 2), turn("b", 30)])

        #expect(activity.firstActivity == at(2))
        #expect(activity.lastActivity == at(30))
        #expect(activity.cwd == "/w")
    }

    @Test func activityRoundTripsThroughJSON() throws {
        let activity = fold([
            turn("a", 0), turn("b", 1, model: haiku, subagent: true),
            .toolStarted(ToolStart(id: "open", name: "Bash", input: ["command": "sleep 9"], at: at(2))),
            .compacted(Compaction(at: at(3), preTokens: 9, postTokens: 1)),
        ])

        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(SessionActivity.self, from: data)

        #expect(decoded == activity)
        #expect(decoded.folding([turn("a", 0)]) == activity.folding([turn("a", 0)]))
    }

    @Test func syntheticTurnLeavesNoBucketUsage() {
        let activity = fold([turn("s", 0, output: 0, model: .synthetic, input: 0)])

        #expect(activity.buckets.isEmpty)
    }

    @Test func syntheticTurnNeverAddsTokens() {
        let activity = fold([turn("a", 0), turn("s", 1, output: 50, model: .synthetic)])

        #expect(total(activity).output == 100)
    }

    @Test func outputAt59MinutesBeforeLatestStaysInChart() {
        let activity = fold([turn("a", 0, output: 3), turn("b", 59 * 60, output: 7)])

        #expect(activity.outputByMinute.count == 2)
    }

    @Test func outputAt60MinutesBeforeLatestLeavesChart() {
        let activity = fold([turn("a", 0, output: 3), turn("b", 60 * 60, output: 7)])

        #expect(activity.outputByMinute.count == 1)
    }

    @Test func subagentToolsAreNotCounted() {
        let activity = fold([
            .toolStarted(ToolStart(id: "t1", name: "Bash", input: ["command": "ls"], at: at(0), isSubagent: true)),
            .toolFinished(ToolFinish(id: "t1", isError: true, exitCode: 1, diff: nil, at: at(1), isSubagent: true)),
        ])

        #expect(activity.buckets.isEmpty)
        #expect(activity.recentTools.isEmpty)
    }
}
