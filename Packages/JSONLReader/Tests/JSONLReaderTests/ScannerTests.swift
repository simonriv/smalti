import Foundation
import Testing

@testable import JSONLReader

@Suite struct ScannerTests {
    private func scan(_ file: URL, _ needle: String, blockSize: Int = JSONLScanner.blockSize, cancelAfter: Int? = nil)
        throws -> [(String, UInt64)]
    {
        var found: [(String, UInt64)] = []
        var checks = 0
        try JSONLScanner.lines(
            containing: Array(needle.utf8), in: file, blockSize: blockSize,
            isCancelled: {
                checks += 1
                return cancelAfter.map { checks > $0 } ?? false
            },
            line: { found.append((String(decoding: $0, as: UTF8.self), $1)) })
        return found
    }

    @Test func findsLinesIgnoringASCIICase() throws {
        let file = try TemporaryFile("one Timeline\ntwo\nthree TIMELINE\n")

        let found = try scan(file.url, "timeline")

        #expect(found.map(\.0) == ["one Timeline", "three TIMELINE"])
        #expect(found.map(\.1) == [0, 17])
    }

    @Test func aLineWithTwoMatchesComesOnce() throws {
        let file = try TemporaryFile("ab ab\n")

        #expect(try scan(file.url, "ab").map(\.0) == ["ab ab"])
    }

    @Test func findsANeedleSplitBetweenBlocks() throws {
        let file = try TemporaryFile("xxxxxxxneedle\nnope\n")

        let found = try scan(file.url, "needle", blockSize: 10)

        #expect(found.map(\.0) == ["xxxxxxxneedle"])
    }

    @Test func findsALineSpanningBlocks() throws {
        let file = try TemporaryFile("a\nbbbbbbbbbbbbbbbbbbbbbbbneedlebbbbbb\nc needle\n")

        let found = try scan(file.url, "needle", blockSize: 8)

        #expect(found.map(\.0) == ["bbbbbbbbbbbbbbbbbbbbbbbneedlebbbbbb", "c needle"])
        #expect(found.map(\.1) == [2, 38])
    }

    @Test func anEmptyNeedleHandsOverEveryLine() throws {
        let file = try TemporaryFile("a\nb\nlast")

        #expect(try scan(file.url, "").map(\.0) == ["a", "b", "last"])
    }

    @Test func keepsNonASCIIBytesAsTheyAre() throws {
        let file = try TemporaryFile("canción\nCANCIÓN\n")

        #expect(try scan(file.url, "canci").map(\.0) == ["canción", "CANCIÓN"])
    }

    @Test func stopsWhenCancelled() throws {
        let file = try TemporaryFile("hit 1\nhit 2\nhit 3\nhit 4\n")

        let found = try scan(file.url, "hit", blockSize: 6, cancelAfter: 1)

        #expect(found.map(\.0) == ["hit 1"])
    }

    @Test func aMissingFileThrows() {
        #expect(throws: JSONLReadError.self) {
            try scan(URL(filePath: "/nonexistent/\(UUID().uuidString)"), "x")
        }
    }
}
