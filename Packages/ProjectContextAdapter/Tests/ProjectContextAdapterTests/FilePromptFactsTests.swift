import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

import ProjectContextAdapter

/// Spec F5, the prompt's facts: repository root and branch from files, changes from `git status`, the runtime's
/// version from its executable, the kube context from the kubeconfig.
@Suite("FilePromptFacts")
struct FilePromptFactsTests {
    /// Answers from a table by command line; counts calls; `nil` for anything else (a timeout or a failure).
    private final class FakeRunner: CommandRunner, @unchecked Sendable {
        // Safe: only mutated under `lock`.
        private let lock = NSLock()
        private var answers: [String: String]
        private var calls: [String] = []

        init(_ answers: [String: String]) {
            self.answers = answers
        }

        func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration) async -> String?
        {
            let line = ([executable] + arguments).joined(separator: " ")
            return lock.withLock {
                calls.append(line)
                return answers[line]
            }
        }

        var callCount: Int {
            lock.withLock { calls.count }
        }

        var recorded: [String] {
            lock.withLock { calls }
        }
    }

    private final class Clock: @unchecked Sendable {
        // Safe: tests set it between awaits, never concurrently.
        var value = Date(timeIntervalSince1970: 100)
    }

    private static let gitStatus = "/usr/bin/git --no-optional-locks status --porcelain=v2 --untracked-files=no"
    private let root = FileManager.default.temporaryDirectory.appending(path: "smalti-facts-\(UUID())")

    private func makeRepo(head: String = "ref: refs/heads/feat/reminders\n") throws -> String {
        let git = root.appending(path: "repo/.git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try head.write(to: git.appending(path: "HEAD"), atomically: true, encoding: .utf8)
        try "index".write(to: git.appending(path: "index"), atomically: true, encoding: .utf8)
        let api = root.appending(path: "repo/apps/api")
        try FileManager.default.createDirectory(at: api, withIntermediateDirectories: true)
        return api.path(percentEncoded: false)
    }

    private func query(_ directory: String, runtimes: [RuntimeKind: String] = [:], kubeconfig: String? = "/nonexistent")
        -> PromptQuery
    {
        PromptQuery(directory: directory, runtimePaths: runtimes, kubeconfig: kubeconfig)
    }

    private func touch(_ name: String, in directory: String) throws {
        try "".write(to: URL(filePath: directory).appending(path: name), atomically: true, encoding: .utf8)
    }

    @Test func repoRootAndBranchComeFromFiles() async throws {
        let directory = try makeRepo()

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(for: query(directory))

        #expect(facts.repoRoot == root.appending(path: "repo").path(percentEncoded: false))
        #expect(facts.branch == "feat/reminders")
    }

    @Test func detachedHeadShowsShortSha() async throws {
        let directory = try makeRepo(head: "0123456789abcdef0123456789abcdef01234567\n")

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(for: query(directory))

        #expect(facts.branch == "0123456")
    }

    @Test func countsModifiedAndStaged() async throws {
        let directory = try makeRepo()
        let porcelain = """
            1 .M N... 100644 100644 100644 a b apps/api/a.ts
            1 M. N... 100644 100644 100644 a b apps/api/b.ts
            1 MM N... 100644 100644 100644 a b apps/api/c.ts
            2 R. N... 100644 100644 100644 a b R100 new.ts\told.ts
            """

        let facts = await FilePromptFacts(runner: FakeRunner([Self.gitStatus: porcelain])).facts(for: query(directory))

        #expect(facts.changes == GitChanges(modified: 2, staged: 3))
    }

    @Test func cleanRepoReportsZeroChanges() async throws {
        let directory = try makeRepo()

        let facts = await FilePromptFacts(runner: FakeRunner([Self.gitStatus: ""])).facts(for: query(directory))

        #expect(facts.changes == GitChanges(modified: 0, staged: 0))
    }

    @Test func slowGitDropsChanges() async throws {
        let directory = try makeRepo()

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(for: query(directory))

        #expect(facts.changes == nil)
        #expect(facts.branch == "feat/reminders")
    }

    /// Block 3 review (I1): only requests within a second share one `git status`; editing a file never touches the
    /// index, so the index cannot be the key.
    @Test func requestsWithinASecondShareOneRun() async throws {
        let directory = try makeRepo()
        let runner = FakeRunner([Self.gitStatus: ""])
        let facts = FilePromptFacts(runner: runner, clock: { Date(timeIntervalSince1970: 100) })

        _ = await facts.facts(for: query(directory))
        _ = await facts.facts(for: query(directory))

        #expect(runner.callCount == 1)
    }

    @Test func laterPromptRunsGitAgainWithIndexUnchanged() async throws {
        let directory = try makeRepo()
        let runner = FakeRunner([Self.gitStatus: ""])
        let now = Clock()
        let facts = FilePromptFacts(runner: runner, clock: { now.value })
        _ = await facts.facts(for: query(directory))

        now.value = now.value.addingTimeInterval(1.5)
        _ = await facts.facts(for: query(directory))

        #expect(runner.callCount == 2)
    }

    @Test func nodeProjectReportsNodeVersion() async throws {
        let directory = try makeRepo()
        try touch("package.json", in: directory)
        let runner = FakeRunner(["/opt/node --version": "v22.11.0\n"])

        let facts = await FilePromptFacts(runner: runner).facts(for: query(directory, runtimes: [.node: "/opt/node"]))

        #expect(facts.runtime == RuntimeVersion(kind: .node, version: "22.11"))
    }

    @Test func bunLockWinsOverPackageJson() async throws {
        let directory = try makeRepo()
        try touch("package.json", in: directory)
        try touch("bun.lockb", in: directory)
        let runner = FakeRunner(["/opt/bun --version": "1.2.3\n", "/opt/node --version": "v22.11.0\n"])

        let facts = await FilePromptFacts(runner: runner).facts(
            for: query(directory, runtimes: [.node: "/opt/node", .bun: "/opt/bun"]))

        #expect(facts.runtime == RuntimeVersion(kind: .bun, version: "1.2"))
    }

    @Test func goUsesGoVersion() async throws {
        let directory = try makeRepo()
        try touch("go.mod", in: directory)
        let runner = FakeRunner(["/opt/go version": "go version go1.24.2 darwin/arm64\n"])

        let facts = await FilePromptFacts(runner: runner).facts(for: query(directory, runtimes: [.go: "/opt/go"]))

        #expect(facts.runtime == RuntimeVersion(kind: .go, version: "1.24"))
    }

    @Test func runtimeWithoutExecutableIsNil() async throws {
        let directory = try makeRepo()
        try touch("pyproject.toml", in: directory)

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(for: query(directory))

        #expect(facts.runtime == nil)
    }

    @Test func runtimeCachedUntilBinaryChanges() async throws {
        let directory = try makeRepo()
        try touch("package.json", in: directory)
        let binary = root.appending(path: "node").path(percentEncoded: false)
        try touch("node", in: root.path(percentEncoded: false))
        let runner = FakeRunner(["\(binary) --version": "v22.11.0", Self.gitStatus: ""])
        let facts = FilePromptFacts(runner: runner)

        _ = await facts.facts(for: query(directory, runtimes: [.node: binary]))
        _ = await facts.facts(for: query(directory, runtimes: [.node: binary]))

        #expect(runner.recorded.filter { $0.hasSuffix("--version") }.count == 1)
    }

    @Test func kubeContextFromKubeconfig() async throws {
        let directory = try makeRepo()
        let kubeconfig = root.appending(path: "kubeconfig")
        try "apiVersion: v1\ncurrent-context: gke-west\nkind: Config\n".write(
            to: kubeconfig, atomically: true, encoding: .utf8)

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(
            for: query(directory, kubeconfig: kubeconfig.path(percentEncoded: false)))

        #expect(facts.kubeContext == "gke-west")
    }

    @Test func noGitDirectoryHasNoRepo() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let facts = await FilePromptFacts(runner: FakeRunner([:])).facts(for: query(root.path(percentEncoded: false)))

        #expect(facts.repoRoot == nil)
        #expect(facts.branch == nil)
        #expect(facts.changes == nil)
    }

    @Test func honorsTheContract() async {
        await PromptFactsContract.verify { FilePromptFacts(runner: FakeRunner([:])) }
    }
}

@Suite("SystemCommandRunner")
struct SystemCommandRunnerTests {
    @Test func returnsStandardOutput() async {
        let output = await SystemCommandRunner().run("/bin/echo", ["hola"], in: "/tmp", timeout: .seconds(2))

        #expect(output == "hola\n")
    }

    @Test func timeoutGivesNilQuickly() async {
        let start = ContinuousClock.now

        let output = await SystemCommandRunner().run("/bin/sleep", ["5"], in: "/tmp", timeout: .milliseconds(100))

        #expect(output == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func failureGivesNil() async {
        #expect(await SystemCommandRunner().run("/usr/bin/false", [], in: "/tmp", timeout: .seconds(2)) == nil)
    }

    @Test func missingExecutableGivesNil() async {
        #expect(await SystemCommandRunner().run("/nonexistent", [], in: "/tmp", timeout: .seconds(2)) == nil)
    }
}
