import Foundation
import Testing

@testable import JSONLReader

@Suite struct LineReaderTests {
    private func lines(_ file: URL, from offset: UInt64 = 0) -> ([(String, UInt64)], JSONLReadOutcome) {
        var read: [(String, UInt64)] = []
        let outcome = JSONLLineReader.read(file, from: offset) { line, at in
            read.append((String(decoding: line, as: UTF8.self), at))
        }
        return (read, outcome)
    }

    @Test func handsOverEachCompleteLineWithItsOffset() throws {
        let file = try TemporaryFile("{\"a\":1}\n{\"b\":22}\n")

        let (read, outcome) = lines(file.url)

        #expect(read.map(\.0) == [#"{"a":1}"#, #"{"b":22}"#])
        #expect(read.map(\.1) == [0, 8])
        #expect(outcome.offset == 17)
        #expect(outcome.failure == nil)
    }

    @Test func leavesALineWithoutNewlineForTheNextRead() throws {
        let file = try TemporaryFile("{\"a\":1}\n{\"b\":")

        let (first, outcome) = lines(file.url)
        try file.append("2}\n")
        let (second, _) = lines(file.url, from: outcome.offset)

        #expect(first.map(\.0) == [#"{"a":1}"#])
        #expect(second.map(\.0) == [#"{"b":2}"#])
        #expect(second.map(\.1) == [8])
    }

    @Test func readsLinesLongerThanOneBlock() throws {
        let long = String(repeating: "x", count: 3 * 1_048_576 + 17)
        let file = try TemporaryFile("{\"t\":\"\(long)\"}\nok\n")

        let (read, _) = lines(file.url)

        #expect(read.count == 2)
        #expect(read[0].0.utf8.count == long.utf8.count + 8)
        #expect(read[1] == ("ok", UInt64(long.utf8.count + 9)))
    }

    @Test func aMissingFileFailsWithoutLines() {
        let (read, outcome) = lines(URL(filePath: "/nonexistent/\(UUID().uuidString).jsonl"), from: 5)

        #expect(read.isEmpty)
        #expect(outcome.offset == 5)
        #expect(outcome.failure != nil)
    }

    /// Review 1 (M10): a closed timeline stops reading a big transcript between blocks.
    @Test func stopsBetweenBlocksWhenCancelled() throws {
        let line = String(repeating: "x", count: 600_000)
        let file = try TemporaryFile((0..<6).map { _ in line }.joined(separator: "\n") + "\n")
        var read = 0
        var checks = 0

        let outcome = JSONLLineReader.read(
            file.url, from: 0,
            isCancelled: {
                checks += 1; return checks > 1
            }
        ) { _, _ in
            read += 1
        }

        #expect(read < 6)
        #expect(outcome.offset < UInt64(6 * 600_001))
    }

    @Test func skipsEmptyLines() throws {
        let file = try TemporaryFile("a\n\nb\n")

        let (read, _) = lines(file.url)

        #expect(read.map(\.0) == ["a", "b"])
        #expect(read.map(\.1) == [0, 3])
    }
}
