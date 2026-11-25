import Foundation
import OpenCodeHarnessAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C2: the fixture's newest session resumes with `opencode -s <id>` in a terminal, its provider pointing at a dead
/// port. OpenCode 2.x leaves `opencode serve --service` behind; the run kills it by the home in its environment.
extension OpenCodeHarnessTests {
    @Suite(
        "OpenCode resume integration", .enabled(if: PtyResume.binary("opencode") != nil, "opencode is not installed"))
    struct ResumeIntegrationTests {
        @Test func resumesFixtureWithRealCommand() throws {
            let fixture = try OpenCodeFixture.description
            let home = try FixtureHome.materialize(fixture)
            let config = home.appending(path: ".config/opencode/opencode.json")
            let text = try String(contentsOf: config, encoding: .utf8)
            try text.replacing(/http:\/\/127\.0\.0\.1:\d+/, with: "http://127.0.0.1:9").write(
                to: config, atomically: true, encoding: .utf8)
            let newest = try #require(try FixtureExpectations.load(from: fixture.source).sessions.first)
            let agent = AgentSnapshot(harness: .opencode, sessionID: newest.id, title: nil, lastState: nil)

            let result = try PtyResume.run(
                .init(
                    command: OpenCodeFixture.harness(home: home).resumeCommand(for: agent),
                    environment: [
                        "HOME": home.path, "XDG_DATA_HOME": home.appending(path: ".local/share").path,
                        "XDG_CONFIG_HOME": home.appending(path: ".config").path,
                        "XDG_STATE_HOME": home.appending(path: ".local/state").path,
                        "XDG_CACHE_HOME": home.appending(path: ".cache").path,
                        "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
                        "TERM": "xterm-256color",
                    ],
                    directory: URL(filePath: newest.directory), needle: "hola fixture B", root: fixture.root))

            #expect(result.found, "screen: \(result.transcript.suffix(800))")
            #expect(result.leftovers.isEmpty, "left running: \(result.leftovers)")
        }
    }
}
