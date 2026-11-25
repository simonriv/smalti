import CodexHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C2: the fixture's newest session resumes with the adapter's real command, in a terminal, without network: the
/// provider points at a dead port, so nothing is asked of any model (spike T1).
extension CodexHarnessTests {
    @Suite("Codex resume integration", .enabled(if: PtyResume.binary("codex") != nil, "codex is not installed"))
    struct ResumeIntegrationTests {
        @Test func resumesFixtureWithRealCommand() throws {
            let fixture = try CodexFixture.description
            let home = try FixtureHome.materialize(fixture)
            let newest = try #require(try FixtureExpectations.load(from: fixture.source).sessions.first)
            try hermeticConfig(home: home, fixture: fixture)
            let agent = AgentSnapshot(harness: .codex, sessionID: newest.id, title: nil, lastState: nil)

            let result = try PtyResume.run(
                .init(
                    command: CodexFixture.harness(home: home).resumeCommand(for: agent),
                    environment: [
                        "HOME": home.path, "CODEX_HOME": home.appending(path: "codex").path,
                        "PATH": "/opt/homebrew/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                    ],
                    directory: URL(filePath: newest.directory), needle: newest.title, root: fixture.root,
                    answers: ["Trust and continue": "\r"]))

            #expect(result.found, "screen: \(result.transcript.suffix(800))")
            #expect(result.leftovers.isEmpty, "left running: \(result.leftovers)")
        }

        private func hermeticConfig(home: URL, fixture: HarnessFixtureDescription) throws {
            let trusted = ["work-a", "work-b"].map {
                "[projects.\"\(fixture.root.appending(path: $0).path)\"]\ntrust_level = \"trusted\"\n"
            }
            let config = """
                model_provider = "dead"
                model = "qwen3:4b"
                check_for_update_on_startup = false
                [model_providers.dead]
                name = "dead"
                base_url = "http://127.0.0.1:9/v1"
                wire_api = "responses"

                """ + trusted.joined()
            try config.write(to: home.appending(path: "codex/config.toml"), atomically: true, encoding: .utf8)
        }
    }
}
