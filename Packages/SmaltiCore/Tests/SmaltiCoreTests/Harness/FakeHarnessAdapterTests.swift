import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// The fake keeps its sessions in `fake-sessions.json`; this checks it against the shared contract, so the contract
/// itself is exercised without any harness installed.
@Suite("Fake harness adapter", .serialized)
struct FakeHarnessAdapterTests {
    @Test func fakeSatisfiesTheHarnessContract() async throws {
        let fixture = try FakeHarnessFixture.make()

        try await HarnessAdapterContract.verify(
            fixture: fixture.description, make: { FakeHarnessAdapter(home: $0) },
            breakSchema: { home in
                let file = home.appending(path: FakeHarnessAdapter.storeName)
                let broken = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(
                    of: "\"directory\"", with: "\"folder\"")
                try broken.write(to: file, atomically: true, encoding: .utf8)
            })
    }

    @Test func keepsPosingAsClaudeForRestoreTests() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: nil, lastState: .waiting)

        #expect(FakeHarnessAdapter().resumeCommand(sessionID: "7f3a") == "fake --resume 7f3a")
    }
}
