import SmaltiCore
import Testing

@Suite("Inherited environment")
struct InheritedEnvironmentTests {
    @Test func claudeCodeSessionVariablesAreDropped() {
        let inherited = [
            "CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_SESSION_ID": "x",
            "CLAUDE_CODE_MESSAGING_TOKEN": "t", "CLAUDE_PID": "42", "CLAUDE_EFFORT": "high",
        ]

        #expect(Set(InheritedEnvironment.agentSessionVariables(in: inherited)) == Set(inherited.keys))
    }

    @Test func everythingElseIsKept() {
        let inherited = ["PATH": "/usr/bin", "HOME": "/Users/s", "ANTHROPIC_API_KEY": "k", "CLAUDE_CONFIG_DIR": "/c"]

        #expect(InheritedEnvironment.agentSessionVariables(in: inherited).isEmpty)
    }
}
