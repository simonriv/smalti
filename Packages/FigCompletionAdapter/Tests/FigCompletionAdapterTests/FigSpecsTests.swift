import FigCompletionAdapter
import Foundation
import SmaltiCore
import Testing

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    // Only touched from the test's own task, one step at a time.
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite("FigSpecs", .serialized)
struct FigSpecsTests {
    private let temp = FileManager.default.temporaryDirectory.appending(path: "smalti-fig-\(UUID())")
    private var userSpecs: URL { temp.appending(path: "completions") }
    private let clock = TestClock()

    private func specs(timeout: Duration = .seconds(1)) -> FigSpecs {
        let clock = clock
        return FigSpecs(user: userSpecs, runner: GeneratorRunner(timeout: timeout), clock: { clock.now })
    }

    private func writeUserSpec(_ name: String, _ source: String) throws {
        try FileManager.default.createDirectory(at: userSpecs, withIntermediateDirectories: true)
        try source.write(to: userSpecs.appending(path: "\(name).js"), atomically: true, encoding: .utf8)
    }

    private func firstGenerator(_ spec: CompletionSpec?, path: [String]) -> GeneratorID? {
        var current = spec
        for name in path { current = current?.subcommands.first { $0.name.contains(name) } }
        return current?.args.first?.generators.first
    }

    @Test func gitSpecHasCheckoutSubcommand() async throws {
        let git = try #require(await specs().spec(for: "git"))

        #expect(git.subcommands.contains { $0.name.contains("checkout") })
    }

    @Test func gitSubcommandsHaveDescriptions() async throws {
        let git = try #require(await specs().spec(for: "git"))

        #expect(git.subcommands.first { $0.name.contains("checkout") }?.description?.isEmpty == false)
    }

    @Test func npmRunArgumentHasScriptGenerator() async throws {
        let npm = await specs().spec(for: "npm")

        #expect(firstGenerator(npm, path: ["run"]) != nil)
    }

    /// Fig's `cd` lists folders with its `filepaths({ showFolders: "only" })` generator, a `custom` one.
    @Test func cdGeneratorListsFolders() async throws {
        let folder = temp.appending(path: "cd-home")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Projects"), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appending(path: "notes.txt").path(percentEncoded: false), contents: nil)
        let specs = specs()
        let generator = try #require(await specs.spec(for: "cd")?.args.first?.generators.first)

        let names = try await specs.generate(generator, tokens: ["cd", ""], in: folder.path(percentEncoded: false)).map(
            \.name)

        #expect(names.contains("Projects/"))
        #expect(!names.contains("notes.txt"))
    }

    @Test func loadSpecSubcommandIsResolved() async throws {
        let xcrun = try #require(await specs().spec(for: "xcrun"))

        #expect(xcrun.subcommands.first { $0.name.contains("simctl") }?.subcommands.isEmpty == false)
    }

    @Test func loadSpecCycleIsNotFollowed() async throws {
        try writeUserSpec(
            "loop", "export default { name: \"loop\", subcommands: [{ name: \"again\", loadSpec: \"loop\" }] };")

        let loop = try #require(await specs().spec(for: "loop"))

        #expect(loop.subcommands.map(\.name) == [["again"]])
    }

    @Test func userSpecOverridesBundled() async throws {
        try writeUserSpec("git", "export default { name: \"git\", subcommands: [{ name: \"only-mine\" }] };")

        let git = try #require(await specs().spec(for: "git"))

        #expect(git.subcommands.map(\.name) == [["only-mine"]])
    }

    @Test func commandsListsBundledAndUser() async throws {
        try writeUserSpec("claude", "export default { name: \"claude\" };")

        let commands = await specs().commands

        #expect(commands.contains("git"))
        #expect(commands.contains("claude"))
        #expect(!commands.contains("git-flow"))
    }

    @Test func brokenUserSpecIsReportedAndBundledStillWorks() async throws {
        try writeUserSpec("broken", "export default { name: ")
        let specs = specs()

        #expect(await specs.spec(for: "broken") == nil)
        #expect(await specs.lastError?.command == "broken")
        #expect(await specs.spec(for: "git") != nil)
    }

    @Test func branchGeneratorListsBranchesInTempRepo() async throws {
        let repo = temp.appending(path: "repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        for arguments in [
            ["init", "-q", "-b", "main"],
            ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "x"],
            ["branch", "feature/smalti-test"],
        ] {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = arguments
            git.currentDirectoryURL = repo
            try git.run()
            git.waitUntilExit()
        }
        let specs = specs()
        let generator = try #require(firstGenerator(await specs.spec(for: "git"), path: ["checkout"]))

        let items = try await specs.generate(
            generator, tokens: ["git", "checkout", ""], in: repo.path(percentEncoded: false))

        #expect(items.map(\.name).contains("feature/smalti-test"))
    }

    @Test func generatorTimeoutThrowsWithCommand() async throws {
        try writeUserSpec(
            "slow", "export default { name: \"slow\", args: { generators: { script: [\"sleep\", \"5\"] } } };")
        let specs = specs(timeout: .milliseconds(200))
        let generator = try #require(await specs.spec(for: "slow")?.args.first?.generators.first)
        let started = Date()

        await #expect(throws: CompletionError.self) {
            try await specs.generate(generator, tokens: ["slow", ""], in: "/tmp")
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func postProcessShapesTheOutput() async throws {
        try writeUserSpec(
            "post",
            """
            export default { name: "post", args: { generators: {
              script: ["printf", "a\\\\nb\\\\n"],
              postProcess: (out) => out.split("\\n").filter(Boolean).map((n) => ({ name: n.toUpperCase(), description: "x" }))
            } } };
            """)
        let specs = specs()
        let generator = try #require(await specs.spec(for: "post")?.args.first?.generators.first)

        let items = try await specs.generate(generator, tokens: ["post", ""], in: "/tmp")

        #expect(items == [Suggestion(name: "A", description: "x"), Suggestion(name: "B", description: "x")])
    }

    @Test func customGeneratorCanRunCommands() async throws {
        try writeUserSpec(
            "custom",
            """
            export default { name: "custom", args: { generators: {
              custom: async (tokens, run) => {
                const { stdout } = await run({ command: "printf", args: ["x y"] });
                return stdout.split(" ").map((name) => ({ name }));
              }
            } } };
            """)
        let specs = specs()
        let generator = try #require(await specs.spec(for: "custom")?.args.first?.generators.first)

        let items = try await specs.generate(generator, tokens: ["custom", ""], in: "/tmp")

        #expect(items.map(\.name) == ["x", "y"])
    }

    @Test func generatorResultIsCachedFor30Seconds() async throws {
        let counter = temp.appending(path: "counter")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try writeUserSpec(
            "count",
            "export default { name: \"count\", args: { generators: { script: \"echo x >> \(counter.path(percentEncoded: false)); wc -l < \(counter.path(percentEncoded: false)) | tr -d \' \'\" } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "count")?.args.first?.generators.first)

        let first = try await specs.generate(generator, tokens: ["count", ""], in: "/tmp")
        clock.now += 29
        let cached = try await specs.generate(generator, tokens: ["count", ""], in: "/tmp")
        clock.now += 2
        let fresh = try await specs.generate(generator, tokens: ["count", ""], in: "/tmp")

        #expect(first.map(\.name) == ["1"])
        #expect(cached == first)
        #expect(fresh.map(\.name) == ["2"])
    }

    @Test func pathsListFoldersAndFilesMatchingThePrefix() async throws {
        let folder = temp.appending(path: "home")
        for name in ["Projects", "Public", ".config"] {
            try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(
            atPath: folder.appending(path: "Pictures.txt").path(percentEncoded: false), contents: nil)
        let specs = specs()
        let path = folder.path(percentEncoded: false)

        #expect(
            Set(await specs.paths(matching: "P", in: path, foldersOnly: false).map(\.name)) == [
                "Projects/", "Public/", "Pictures.txt",
            ])
        #expect(
            Set(await specs.paths(matching: "P", in: path, foldersOnly: true).map(\.name)) == ["Projects/", "Public/"])
        #expect(await specs.paths(matching: "", in: path, foldersOnly: true).map(\.name).contains(".config/") == false)
        #expect(await specs.paths(matching: ".c", in: path, foldersOnly: true).map(\.name) == [".config/"])
    }

    @Test func pathsDescendIntoTheTypedFolder() async throws {
        let folder = temp.appending(path: "tree")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "src/main"), withIntermediateDirectories: true)

        let names = await specs().paths(matching: "src/m", in: folder.path(percentEncoded: false), foldersOnly: true)
            .map(\.name)

        #expect(names == ["src/main/"])
    }
}
