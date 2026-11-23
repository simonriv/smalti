import Foundation
import SmaltiCore
import Testing

func historyEntry(
    _ command: String, in directory: String = "/repo", exit: Int? = 0, at seconds: TimeInterval = 0,
    pane: PaneID = HistoryFixture.pane
) -> HistoryEntry {
    HistoryEntry(
        command: command, directory: directory, exit: exit, duration: 1, date: Date(timeIntervalSince1970: seconds),
        pane: pane)
}

enum HistoryFixture {
    static let pane = PaneID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID())
    static let otherPane = PaneID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2") ?? UUID())
}

@Suite("HistoryIndex")
struct HistoryIndexTests {
    @Test func limitZeroKeepsNothing() {
        let index = HistoryIndex(entries: [historyEntry("ls")], limit: 0)

        #expect(index.count == 0)
        #expect(index.stats(for: "ls") == nil)
    }

    @Test func limitOneKeepsTheMostRecent() {
        let index = HistoryIndex(entries: [historyEntry("ls", at: 1), historyEntry("pwd", at: 2)], limit: 1)

        #expect(index.count == 1)
        #expect(index.stats(for: "pwd")?.uses == 1)
        #expect(index.stats(for: "ls") == nil)
    }

    @Test func largeLimitKeepsEverything() {
        let entries = (0..<1_000).map { historyEntry("cmd \($0 % 10)", at: TimeInterval($0)) }

        let index = HistoryIndex(entries: entries, limit: 100_000)

        #expect(index.count == 1_000)
        #expect(index.stats(for: "cmd 3")?.uses == 100)
    }

    @Test func appendPastLimitEvictsOldest() {
        var index = HistoryIndex(entries: [historyEntry("ls", at: 1), historyEntry("ls", at: 2)], limit: 2)

        index.append(historyEntry("pwd", at: 3))

        #expect(index.count == 2)
        #expect(index.stats(for: "ls")?.uses == 1)
        #expect(index.stats(for: "pwd")?.uses == 1)
    }

    @Test func statsCountUsesPerDirectory() {
        let index = HistoryIndex(
            entries: [
                historyEntry("make", in: "/a", at: 1), historyEntry("make", in: "/a", at: 2),
                historyEntry("make", in: "/b", exit: 2, at: 3),
            ], limit: 10)

        let stats = index.stats(for: "make")

        #expect(stats?.uses == 3)
        #expect(stats?.usesByDirectory == ["/a": 2, "/b": 1])
        #expect(stats?.lastUsed == Date(timeIntervalSince1970: 3))
        #expect(stats?.lastExit == 2)
    }

    @Test func commandsInDirectoryFiltersOthers() {
        let index = HistoryIndex(
            entries: [historyEntry("make", in: "/a"), historyEntry("ls", in: "/b")], limit: 10)

        #expect(index.commands(in: "/a").map(\.command) == ["make"])
        #expect(Set(index.commands(in: nil).map(\.command)) == ["make", "ls"])
    }

    @Test func successorsCountOnlySameDirectory() {
        let index = HistoryIndex(
            entries: [
                historyEntry("git add .", in: "/a", at: 1), historyEntry("git commit", in: "/a", at: 2),
                historyEntry("git add .", in: "/b", at: 3), historyEntry("git push", in: "/b", at: 4),
            ], limit: 10)

        #expect(index.successors(of: "git add .", in: "/a") == ["git commit": 1])
        #expect(index.successors(of: "git add .", in: "/b") == ["git push": 1])
    }

    @Test func successorsFollowTheSamePane() {
        let index = HistoryIndex(
            entries: [
                historyEntry("git add .", at: 1), historyEntry("htop", at: 2, pane: HistoryFixture.otherPane),
                historyEntry("git commit", at: 3),
            ], limit: 10)

        #expect(index.successors(of: "git add .", in: "/repo") == ["git commit": 1])
    }

    @Test func evictionForgetsTheSuccessorPair() {
        var index = HistoryIndex(
            entries: [historyEntry("a", at: 1), historyEntry("b", at: 2), historyEntry("c", at: 3)], limit: 3)

        index.append(historyEntry("d", at: 4))
        index.append(historyEntry("e", at: 5))

        #expect(index.successors(of: "a", in: "/repo").isEmpty)
        #expect(index.successors(of: "b", in: "/repo").isEmpty)
        #expect(index.successors(of: "c", in: "/repo") == ["d": 1])
    }

    @Test func fixesFollowSameFailedCommand() {
        let index = HistoryIndex(
            entries: [
                historyEntry("git push", exit: 128, at: 1), historyEntry("git push -u origin main", at: 2),
                historyEntry("git push", exit: 0, at: 3), historyEntry("ls", at: 4),
            ], limit: 10)

        #expect(index.fixes(after: "git push") == ["git push -u origin main": 1])
    }

    @Test func rerunningTheSameCommandIsNotAFix() {
        let index = HistoryIndex(
            entries: [historyEntry("make", exit: 2, at: 1), historyEntry("make", exit: 0, at: 2)], limit: 10)

        #expect(index.fixes(after: "make").isEmpty)
    }

    // Review m9: word usage is kept incrementally, eviction included.
    @Test func wordUsageCountsUsesOfCommandsContainingTheWord() {
        var index = HistoryIndex(
            entries: [historyEntry("git cherry-pick a", at: 1), historyEntry("git cherry-pick a", at: 2)], limit: 2)

        #expect(index.uses(ofWord: "cherry-pick") == 2)
        index.append(historyEntry("ls", at: 3))
        #expect(index.uses(ofWord: "cherry-pick") == 1)
        #expect(index.uses(ofWord: "absent") == 0)
    }

    // Mutation survivors (F4 close).
    @Test func unknownExitIsNotAFailure() {
        #expect(!historyEntry("ls", exit: nil).hasFailed)
    }

    @Test func olderEntryAddedLaterKeepsTheNewestUse() {
        let index = HistoryIndex(
            entries: [historyEntry("make", exit: 0, at: 200), historyEntry("make", exit: 2, at: 100)], limit: 10)

        #expect(index.stats(for: "make")?.lastUsed == Date(timeIntervalSince1970: 200))
        #expect(index.stats(for: "make")?.lastExit == 0)
    }

    @Test func evictionKeepsTheDirectoryCountOfTheRest() {
        var index = HistoryIndex(entries: [], limit: 2)
        for second in 1...3 { index.append(historyEntry("ls", at: Double(second))) }

        #expect(index.stats(for: "ls")?.usesByDirectory == ["/repo": 2])
    }

    @Test func evictionStaysRightAcrossStorageCompaction() {
        var index = HistoryIndex(entries: [], limit: 10)
        for number in 0..<3_000 { index.append(historyEntry("c\(number)", at: Double(number))) }

        #expect(Set(index.commands(in: nil).map(\.command)) == Set((2_990..<3_000).map { "c\($0)" }))
    }
}
