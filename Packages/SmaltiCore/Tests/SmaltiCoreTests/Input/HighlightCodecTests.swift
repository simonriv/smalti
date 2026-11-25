import SmaltiCore
import Testing

@Suite("HighlightCodec")
struct HighlightCodecTests {
    @Test func encodesCompactSpans() {
        let spans = [HighlightSpan(range: 0..<3, role: .command), HighlightSpan(range: 4..<6, role: .option)]

        #expect(InputProtocol.encode(.highlight(seq: 7, spans)) == "highlight\t7\t0,3,c 4,6,o")
    }

    @Test func emptySpansEncodeEmptyField() {
        #expect(InputProtocol.encode(.highlight(seq: 2, [])) == "highlight\t2\t")
    }

    @Test func truncatesWithoutSplittingASpan() {
        let spans = (0..<1000).map { HighlightSpan(range: ($0 * 10)..<($0 * 10 + 5), role: .option) }

        let encoded = InputProtocol.encode(.highlight(seq: 1, spans))

        #expect(encoded.utf8.count + 1 <= InputProtocol.maximumAnswerBytes)
        let fields = encoded.split(separator: "\t", omittingEmptySubsequences: false)[2].split(separator: " ")
        #expect(fields.allSatisfy { $0.split(separator: ",").count == 3 && $0.hasSuffix(",o") })
        #expect(fields.first == "0,5,o")
        #expect(fields.count < 1000)
        #expect(fields.last == "\((fields.count - 1) * 10),\((fields.count - 1) * 10 + 5),o")
    }
}
