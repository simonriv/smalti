import Testing

@testable import SmaltiCore

/// F4: evicted slots are dropped once there are more than 1024 of them and they are over half the storage, so
/// eviction stays amortized O(1) (pinned at block 2 of F5.5: the mutants of this rule had no test).
@Suite("HistoryIndex compaction")
struct HistoryCompactionTests {
    @Test func compactsPastBothThresholds() {
        #expect(HistoryIndex.shouldCompact(head: 1025, storage: 2049))
    }

    @Test func notAtTheHeadThreshold() {
        #expect(!HistoryIndex.shouldCompact(head: 1024, storage: 1500))
    }

    @Test func notAtExactlyHalf() {
        #expect(!HistoryIndex.shouldCompact(head: 1025, storage: 2050))
    }
}
