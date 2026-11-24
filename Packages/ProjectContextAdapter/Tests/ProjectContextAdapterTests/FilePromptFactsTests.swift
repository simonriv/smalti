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

        func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration)
            async throws(CommandError) -> String
        {
            let line = ([executable] + arguments).joined(separator: " ")
            let answer = lock.withLock {
                calls.append(line)
                return answers[line]
            }
            guard let answer else { throw .timedOut }
            return answer
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

    private static let gitStatus =
        "\(FilePromptFacts.git) --no-optional-locks status --porcelain=v2 --untracked-files=no"
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
    @Test func returnsStandardOutput() async throws {
        let output = try await SystemCommandRunner().run("/bin/echo", ["hola"], in: "/tmp", timeout: .seconds(2))

        #expect(output == "hola\n")
    }

    @Test func timeoutThrowsQuickly() async {
        let start = ContinuousClock.now

        await #expect(throws: CommandError.timedOut) {
            try await SystemCommandRunner().run("/bin/sleep", ["5"], in: "/tmp", timeout: .milliseconds(100))
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func failureThrowsItsStatus() async {
        await #expect(throws: CommandError.failed(status: 1)) {
            try await SystemCommandRunner().run("/usr/bin/false", [], in: "/tmp", timeout: .seconds(2))
        }
    }

    @Test func missingExecutableCannotStart() async {
        await #expect(throws: CommandError.couldNotStart) {
            try await SystemCommandRunner().run("/nonexistent", [], in: "/tmp", timeout: .seconds(2))
        }
    }

    /// Block 3 review (I3): a grandchild that keeps standard output open must not hold the answer past the child.
    @Test func grandchildHoldingOutputDoesNotBlock() async throws {
        let start = ContinuousClock.now

        let output = try await SystemCommandRunner().run(
            "/bin/sh", ["-c", "sleep 5 & echo hola"], in: "/tmp", timeout: .seconds(3))

        #expect(output == "hola\n")
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func largeOutputIsReadWhole() async throws {
        let output = try await SystemCommandRunner().run(
            "/bin/sh", ["-c", "yes 0123456789 | head -c 1000000"], in: "/tmp", timeout: .seconds(5))

        #expect(output.utf8.count == 1_000_000)
    }
}

/// Block 3 review (M5, M6): version shims answer per project; `KUBECONFIG` may list several files.
@Suite("FilePromptFacts · review")
struct FilePromptFactsReviewTests {
    private final class CountingRunner: CommandRunner, @unchecked Sendable {
        // Safe: only mutated under `lock`.
        private let lock = NSLock()
        private var count = 0

        func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration)
            async throws(CommandError) -> String
        {
            lock.withLock { count += 1 }
            return "v1.0.0"
        }

        var calls: Int { lock.withLock { count } }
    }

    private let root = FileManager.default.temporaryDirectory.appending(path: "smalti-facts-review-\(UUID())")

    private func project(_ name: String) throws -> String {
        let directory = root.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "".write(to: directory.appending(path: "package.json"), atomically: true, encoding: .utf8)
        return directory.path(percentEncoded: false)
    }

    @Test func versionShimAnswersPerProject() async throws {
        let shim = root.appending(path: "shims/node")
        try FileManager.default.createDirectory(at: shim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: shim, atomically: true, encoding: .utf8)
        let runner = CountingRunner()
        let facts = FilePromptFacts(runner: runner)
        let paths: [RuntimeKind: String] = [.node: shim.path(percentEncoded: false)]

        _ = await facts.facts(for: PromptQuery(directory: try project("a"), runtimePaths: paths, kubeconfig: "/none"))
        _ = await facts.facts(for: PromptQuery(directory: try project("b"), runtimePaths: paths, kubeconfig: "/none"))

        #expect(runner.calls == 2)
    }

    @Test func kubeconfigWithSeveralFilesUsesTheFirstContext() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let second = root.appending(path: "second")
        try "current-context: gke-west\n".write(to: second, atomically: true, encoding: .utf8)
        let list = "/nonexistent/first:" + second.path(percentEncoded: false)

        let facts = await FilePromptFacts(runner: CountingRunner()).facts(
            for: PromptQuery(directory: root.path(percentEncoded: false), runtimePaths: [:], kubeconfig: list))

        #expect(facts.kubeContext == "gke-west")
    }
}

/// T17: the real `git` in a real repository, as the app runs it.
@Suite("FilePromptFacts with git")
struct FilePromptFactsGitTests {
    private func shell(_ script: String, in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        // Block 5 review (M11): a setup that fails says so, not as a wrong branch later.
        #expect(process.terminationStatus == 0, "setup failed: \(script)")
    }

    @Test func modifiedFileIsCounted() async throws {
        let repository = FileManager.default.temporaryDirectory.appending(path: "smalti-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository) }
        try shell(
            "git init -q -b feat && echo a >f && git add f && git -c user.email=t@t -c user.name=t commit -qm i "
                + "&& echo b >f", in: repository)

        let facts = await FilePromptFacts().facts(
            for: PromptQuery(directory: repository.path(percentEncoded: false), runtimePaths: [:], kubeconfig: nil))

        #expect(facts.branch == "feat")
        #expect(facts.changes == GitChanges(modified: 1, staged: 0))
    }
}

/// T17: `/usr/bin/git` is xcrun's shim, which needs over a second the first time in a process and is killed at the
/// 300 ms limit before it can cache anything: the prompt never had changes in the app. A real git comes first.
@Suite("GitLocator")
struct GitLocatorTests {
    @Test func firstExecutableCandidateWins() {
        let found = GitLocator.first(of: ["/a/git", "/b/git", "/usr/bin/git"]) {
            $0 == "/b/git" || $0 == "/usr/bin/git"
        }

        #expect(found == "/b/git")
    }

    @Test func theShimIsTheLastResort() {
        #expect(GitLocator.first(of: GitLocator.candidates) { _ in false } == "/usr/bin/git")
        #expect(GitLocator.candidates.last == "/usr/bin/git")
    }

    @Test func homebrewAndDeveloperToolsComeBeforeTheShim() {
        #expect(
            GitLocator.candidates == [
                "/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/git", "/usr/bin/git",
            ])
    }
}
