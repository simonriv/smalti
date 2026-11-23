/// Variables a parent coding-agent session leaves in the environment of whatever it launches. If Smalti is started
/// from inside a Claude Code session, every Claude in its panes would otherwise believe it is a child session (and
/// stop saving transcripts, so `--resume` breaks). The user's own settings (`CLAUDE_CONFIG_DIR`, API keys) stay.
public enum InheritedEnvironment {
    private static let names: Set<String> = ["CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT"]
    private static let prefixes = ["CLAUDE_CODE_"]

    public static func agentSessionVariables(in environment: [String: String]) -> [String] {
        environment.keys.filter { name in names.contains(name) || prefixes.contains { name.hasPrefix($0) } }
    }
}
