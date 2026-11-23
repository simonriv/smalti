import SmaltiCore
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

@Suite("HarnessRegistry")
struct HarnessRegistryTests {
    struct Other: HarnessAdapter {
        let harness = HarnessID.claude
        func resumeCommand(for agent: AgentSnapshot) -> String { "other" }
    }

    @Test func firstAdapterForAHarnessWins() {
        let registry = HarnessRegistry([FakeHarnessAdapter(), Other()])
        let agent = AgentSnapshot(harness: .claude, sessionID: "1", title: nil, lastState: .working)

        #expect(registry.adapter(for: .claude)?.resumeCommand(for: agent) == "fake --resume 1")
    }
}
