import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C2: the fixture's newest session resumes with `claude --resume <id>` in a terminal. Claude shows a saved session
/// without logging in once its onboarding is marked done and the folder trusted (spike T1); nothing is sent.
extension ClaudeHarnessTests {
    @Suite("Claude resume integration", .enabled(if: PtyResume.binary("claude") != nil, "claude is not installed"))
    struct ResumeIntegrationTests {
        @Test func resumesFixtureWithRealCommand() throws {
            let fixture = try ClaudeFixture.description
            let home = try FixtureHome.materialize(fixture)
            try onboardingDone(home: home, fixture: fixture)
            let newest = try #require(try FixtureExpectations.load(from: fixture.source).sessions.first)
            let binary = try #require(PtyResume.binary("claude")).deletingLastPathComponent().path

            let result = try PtyResume.run(
                .init(
                    command: ClaudeFixture.harness(home: home).resumeCommand(sessionID: newest.id),
                    environment: [
                        "HOME": home.path, "CLAUDE_CONFIG_DIR": home.appending(path: ".claude").path,
                        "PATH": "\(binary):/opt/homebrew/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                    ],
                    directory: URL(filePath: newest.directory), needle: "<redacted>", root: fixture.root))

            #expect(result.found, "screen: \(result.transcript.suffix(800))")
            #expect(result.leftovers.isEmpty, "left running: \(result.leftovers)")
        }

        private func onboardingDone(home: URL, fixture: HarnessFixtureDescription) throws {
            let trusted = ["work-a", "work-b"].map { fixture.root.appending(path: $0).path }
            let projects = Dictionary(
                uniqueKeysWithValues: trusted.map {
                    ($0, ["hasTrustDialogAccepted": true, "hasCompletedProjectOnboarding": true])
                })
            let settings: [String: Any] = ["hasCompletedOnboarding": true, "theme": "dark", "projects": projects]
            try JSONSerialization.data(withJSONObject: settings).write(to: home.appending(path: ".claude/.claude.json"))
        }
    }
}
