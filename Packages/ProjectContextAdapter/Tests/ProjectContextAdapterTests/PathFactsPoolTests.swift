import Foundation
import Testing

@testable import ProjectContextAdapter

/// Review 1 (I4): `lstat` on a stuck file system (a hung network mount) blocks its thread, so it must never run on
/// the cooperative pool shared by the whole app: it runs on the adapter's own queue.
@Suite("FileSystemPathFacts · stuck disk")
struct PathFactsPoolTests {
    private final class Record: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool] = []
        var all: [Bool] { lock.withLock { values } }
        func add(_ value: Bool) { lock.withLock { values.append(value) } }
    }

    @Test func lookupsRunOnTheAdapterQueue() async {
        let record = Record()
        let facts = FileSystemPathFacts(mode: { _ in
            record.add(FileSystemPathFacts.isOnLookupQueue)
            return nil
        })

        _ = await facts.kind(of: "/Volumes/nas/a")

        #expect(record.all == [true])
    }
}
