import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Persistence contracts (in memory)")
struct PersistenceContractTests {
    @Test func inMemoryArchiveSatisfiesContract() throws {
        try SessionArchiveContract.verify { InMemorySessionArchive() }
    }

    @Test func inMemoryLayoutsSatisfyContract() throws {
        try NamedLayoutsContract.verify { InMemoryNamedLayouts() }
    }

    @Test func fakeHarnessSatisfiesContract() {
        HarnessAdapterContract.verify(FakeHarnessAdapter())
    }
}
