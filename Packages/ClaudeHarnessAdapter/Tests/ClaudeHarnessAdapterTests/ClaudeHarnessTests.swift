import ClaudeHarnessAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("ClaudeHarness")
struct ClaudeHarnessTests {
    private func agent(_ id: String) -> AgentSnapshot {
        AgentSnapshot(harness: .claude, sessionID: id, title: nil, lastState: .waiting)
    }

    @Test func harnessIsClaude() {
        #expect(ClaudeHarness().harness == .claude)
    }

    @Test func resumeCommandUsesSessionID() {
        #expect(ClaudeHarness().resumeCommand(for: agent("7f3a9c2e")) == "claude --resume 7f3a9c2e")
    }

    @Test func sessionIDIsShellEscaped() {
        #expect(ClaudeHarness().resumeCommand(for: agent("a'b c")) == #"claude --resume 'a'\''b c'"#)
    }

    @Test func claudeSatisfiesTheHarnessContract() {
        HarnessAdapterContract.verify(ClaudeHarness())
    }
}
