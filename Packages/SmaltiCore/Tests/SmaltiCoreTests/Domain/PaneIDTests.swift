import Foundation
import SmaltiCore
import Testing

@Suite("PaneID")
struct PaneIDTests {
    @Test func newIdentifiersAreUnique() {
        #expect(PaneID() != PaneID())
    }

    @Test func descriptionIsTheRawUUID() throws {
        let uuid = try #require(UUID(uuidString: "7F3A0000-0000-4000-8000-000000000001"))

        #expect(PaneID(rawValue: uuid).description == uuid.uuidString)
    }
}
