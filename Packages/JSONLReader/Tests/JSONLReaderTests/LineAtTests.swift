import Foundation
import Testing

@testable import JSONLReader

@Suite struct LineAtTests {
    @Test func readsTheExactBytesOfOneLine() throws {
        let file = try TemporaryFile("{\"a\":1}\n{\"b\":\"ñ\"}\n")

        let line = try JSONLLineAt.line(in: file.url, at: 8, length: 10)

        #expect(String(decoding: line, as: UTF8.self) == #"{"b":"ñ"}"#)
    }

    @Test func aMissingFileIsMissing() {
        let path = "/nonexistent/\(UUID().uuidString).jsonl"

        #expect(throws: JSONLReadError.missing(path: path)) {
            try JSONLLineAt.line(in: URL(filePath: path), at: 0, length: 1)
        }
    }

    @Test func aRangePastTheEndIsUnreadable() throws {
        let file = try TemporaryFile("abc\n")

        #expect(throws: JSONLReadError.self) {
            try JSONLLineAt.line(in: file.url, at: 2, length: 10)
        }
    }

    @Test func identityChangesWhenTheFileIsReplaced() throws {
        let file = try TemporaryFile("abc\n")
        let before = try #require(JSONLFileIdentity.of(file.url))

        try FileManager.default.removeItem(at: file.url)
        try Data("abcdef\n".utf8).write(to: file.url)
        let after = try #require(JSONLFileIdentity.of(file.url))

        #expect(before.size == 4)
        #expect(after.size == 7)
        #expect(JSONLFileIdentity.of(URL(filePath: "/nonexistent/x")) == nil)
    }
}
