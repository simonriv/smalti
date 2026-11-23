import Foundation
import SmaltiCore
import Testing

@Suite("MessageOwners")
struct MessageOwnersTests {
    private typealias F = ObservatoryFixtures
    private let at = Date(timeIntervalSince1970: 1_795_000_000)

    private func ids(_ records: [TranscriptRecord]) -> [String] {
        records.compactMap { record in
            guard case .assistantTurn(let turn) = record else { return nil }
            return turn.messageID
        }
    }

    @Test func firstSessionKeepsAMessage() {
        var owners = MessageOwners()

        let source = owners.claim([F.turn("m1", at: at)], for: "source")
        let fork = owners.claim([F.turn("m1", at: at), F.turn("m2", at: at)], for: "fork")

        #expect(ids(source) == ["m1"])
        #expect(ids(fork) == ["m2"])
    }

    @Test func aSessionKeepsItsOwnRepeats() {
        var owners = MessageOwners()
        _ = owners.claim([F.turn("m1", at: at)], for: "s")

        #expect(ids(owners.claim([F.turn("m1", at: at)], for: "s")) == ["m1"])
    }

    @Test func otherRecordsPassThrough() {
        var owners = MessageOwners()
        _ = owners.claim([F.turn("m1", at: at)], for: "source")
        let tool = TranscriptRecord.toolStarted(ToolStart(id: "t", name: "Bash", input: [:], at: at))

        #expect(owners.claim([tool], for: "fork") == [tool])
    }

    @Test func releasingASessionFreesItsMessages() {
        var owners = MessageOwners()
        _ = owners.claim([F.turn("m1", at: at)], for: "source")

        owners.release("source")

        #expect(ids(owners.claim([F.turn("m1", at: at)], for: "fork")) == ["m1"])
    }

    @Test func sourcesComeBeforeDerivedSessions() {
        let order = MessageOwners.sourcesFirst(["fork", "a", "b"], isDerived: { $0 == "fork" })

        #expect(order == ["a", "b", "fork"])
    }

    @Test func ownersRoundTripThroughJSON() throws {
        var owners = MessageOwners()
        _ = owners.claim([F.turn("m1", at: at)], for: "source")

        let decoded = try JSONDecoder().decode(MessageOwners.self, from: JSONEncoder().encode(owners))

        #expect(decoded == owners)
    }
}
