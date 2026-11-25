import Foundation
import Testing

@testable import OTLPReceiverAdapter

/// The parser on its own, fed byte by byte: no socket timing involved.
@Suite("HTTP request parser")
struct HTTPRequestParserTests {
    private let request = Data(
        "POST /v1/logs HTTP/1.1\r\nAuthorization: Bearer t\r\nContent-Length: 5\r\n\r\nhello".utf8)

    @Test func byteByByteGivesOneRequestAtTheLastByte() {
        var parser = HTTPRequestParser(maximumBody: 100)
        var items: [ParsedItem] = []

        for (offset, byte) in request.enumerated() {
            let produced = parser.feed(Data([byte]))
            if offset < request.count - 1 { #expect(produced.isEmpty) }
            items += produced
        }

        #expect(
            items == [
                .request(
                    HTTPRequest(
                        method: "POST", path: "/v1/logs",
                        headers: ["authorization": "Bearer t", "content-length": "5"],
                        body: Data("hello".utf8)))
            ])
    }

    @Test func twoRequestsInOneFeed() {
        var parser = HTTPRequestParser(maximumBody: 100)

        #expect(parser.feed(request + request).count == 2)
    }

    @Test func nothingAfterAFailure() {
        var parser = HTTPRequestParser(maximumBody: 100)

        #expect(parser.feed(Data("BROKEN\r\n\r\n".utf8)) == [.failure(status: 400)])
        #expect(parser.feed(request).isEmpty)
    }

    @Test func headOverTheLimitIs400() {
        var parser = HTTPRequestParser(maximumBody: 100)

        let items = parser.feed(Data(repeating: UInt8(ascii: "a"), count: HTTPRequestParser.maximumHeadBytes + 1))

        #expect(items == [.failure(status: 400)])
    }
}
