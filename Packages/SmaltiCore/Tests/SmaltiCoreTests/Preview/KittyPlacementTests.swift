import Foundation
import SmaltiCore
import Testing

/// Spec F5.5: one thumbnail as kitty graphics commands, PNG in 4096-byte base64 chunks, cursor left in place.
@Suite("KittyPlacement")
struct KittyPlacementTests {
    private let escape = "\u{1B}_G"
    private let terminator = "\u{1B}\\"

    @Test func smallImageIsOneCommand() {
        let png = Data([1, 2, 3])

        let sequences = KittyPlacement.sequences(png: png, fitting: .columns(12))

        #expect(sequences == ["\(escape)a=T,f=100,q=2,C=1,c=12,m=0;AQID\(terminator)"])
    }

    /// Final review I1: one dimension only, so the terminal keeps the image's proportion.
    @Test func tallImageIsSentByRows() {
        let sequences = KittyPlacement.sequences(png: Data([1, 2, 3]), fitting: .rows(6))

        #expect(sequences == ["\(escape)a=T,f=100,q=2,C=1,r=6,m=0;AQID\(terminator)"])
    }

    @Test func chunksOf4096WithMoreFlag() {
        let png = Data(repeating: 7, count: 10_000)  // 13 336 base64 characters

        let sequences = KittyPlacement.sequences(png: png, fitting: .columns(12))

        #expect(sequences.count == 4)
        #expect(sequences[0].hasPrefix("\(escape)a=T,f=100,q=2,C=1,c=12,m=1;"))
        #expect(sequences[1].hasPrefix("\(escape)m=1;"))
        #expect(sequences[3].hasPrefix("\(escape)m=0;"))
        #expect(sequences.allSatisfy { $0.hasSuffix(terminator) })
    }

    @Test func payloadIsTheWholeBase64WithoutBreaks() {
        let png = Data((0..<9000).map { UInt8($0 % 251) })

        let payload = KittyPlacement.sequences(png: png, fitting: .columns(12)).map { sequence in
            String(sequence.split(separator: ";", maxSplits: 1)[1].dropLast(2))
        }

        #expect(payload.allSatisfy { $0.count <= 4096 && !$0.contains("\n") })
        #expect(payload.joined() == png.base64EncodedString())
    }

    @Test func emptyDataGivesNoCommands() {
        #expect(KittyPlacement.sequences(png: Data(), fitting: .columns(12)).isEmpty)
    }
}
