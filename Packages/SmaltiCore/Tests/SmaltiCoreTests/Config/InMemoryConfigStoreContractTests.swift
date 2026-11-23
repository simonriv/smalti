import SmaltiCoreTestSupport
import Testing

@Suite("InMemoryConfigStore")
struct InMemoryConfigStoreContractTests {
    @MainActor
    @Test func inMemoryStoreSatisfiesContract() throws {
        try ConfigStoreContract.verify(InMemoryConfigStoreHarness())
    }
}
