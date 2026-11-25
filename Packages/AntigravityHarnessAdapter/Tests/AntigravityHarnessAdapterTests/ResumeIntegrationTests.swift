import AntigravityHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C2: the fixture's newest conversation resumes with `agy --conversation <id>` in a terminal. Antigravity needs a
/// login, which never goes to the repo: it is copied from the recording home in `scripts/harnesses/recording.local`.
extension AntigravityHarnessTests {
    static let login = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts/harnesses/recording.local/antigravity/login-home")
    static let loginFiles = [
        ".gemini/antigravity-cli/antigravity-oauth-token",
        "Library/Application Support/antigravity/credential-user-scope",
    ]
    static var canRun: Bool {
        PtyResume.binary("agy") != nil
            && FileManager.default.fileExists(atPath: login.appending(path: loginFiles[0]).path)
    }

    @Suite("Antigravity resume integration", .enabled(if: canRun, "agy or its recorded login is missing"))
    struct ResumeIntegrationTests {
        @Test func resumesFixtureWithRealCommand() throws {
            let fixture = try AntigravityFixture.description
            let home = try FixtureHome.materialize(fixture)
            try copyLogin(into: home)
            let newest = try #require(try FixtureExpectations.load(from: fixture.source).sessions.first)

            let result = try PtyResume.run(
                .init(
                    command: AntigravityFixture.harness(home: home).resumeCommand(sessionID: newest.id),
                    environment: [
                        "HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                        "USER": NSUserName(),
                    ],
                    directory: URL(filePath: newest.directory), needle: newest.title, root: fixture.root))

            #expect(result.found, "screen: \(result.transcript.suffix(800))")
            #expect(result.leftovers.isEmpty, "left running: \(result.leftovers)")
        }

        private func copyLogin(into home: URL) throws {
            for file in AntigravityHarnessTests.loginFiles {
                let source = AntigravityHarnessTests.login.appending(path: file)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let target = home.appending(path: file)
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }
}
