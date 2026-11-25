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
}

@Suite("HarnessRegistry")
struct HarnessRegistryTests {
    struct Other: HarnessAdapter {
        let harness: HarnessID
        let process: String
        func detect(_ candidate: ForegroundProcess) -> Bool { ProcessNames.matches(candidate, [process]) }
        func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] { [] }
        func resumeCommand(sessionID: String) -> String { "other" }
        func continueCommand() -> String { "other -c" }
        func forkCommand(sessionID: String) -> String? { nil }
        func sessionID(fromCommandLine arguments: [String]) -> String? { nil }
    }

    @Test func firstAdapterForAHarnessWins() {
        let registry = HarnessRegistry([FakeHarnessAdapter(), Other(harness: .claude, process: "other")])
        let agent = AgentSnapshot(harness: .claude, sessionID: "1", title: nil, lastState: .working)

        #expect(registry.adapter(for: .claude)?.resumeCommand(sessionID: "1") == "fake --resume 1")
        #expect(registry.all.count == 1)
    }

    @Test func findsTheAdapterRunningAsTheProcess() {
        let registry = HarnessRegistry([FakeHarnessAdapter(), Other(harness: .codex, process: "codex")])

        #expect(registry.adapter(detecting: ForegroundProcess(name: "codex"))?.harness == .codex)
        #expect(registry.adapter(detecting: ForegroundProcess(name: "zsh")) == nil)
    }

    @Test func processNamesCompareTheLastPathComponent() {
        let wrapped = ForegroundProcess(name: "node", commandLine: ["/opt/homebrew/Caskroom/x/antigravity", "-c"])

        #expect(ProcessNames.matches(wrapped, ["antigravity"]))
        #expect(!ProcessNames.matches(ForegroundProcess(name: "antigravity-helper"), ["antigravity"]))
    }

    @Test func valueAfterFlagSkipsMissingOrFlagValues() {
        #expect(ProcessNames.value(after: ["resume"], in: ["codex", "resume", "0198"]) == "0198")
        #expect(ProcessNames.value(after: ["resume"], in: ["codex", "resume"]) == nil)
        #expect(ProcessNames.value(after: ["resume"], in: ["codex", "resume", "--last"]) == nil)
        #expect(ProcessNames.value(after: ["-s"], in: ["opencode", "-s", ""]) == nil)
        #expect(ProcessNames.value(after: ["-s"], in: ["opencode", "-s", "ses\u{15}1"]) == nil)
    }
}
