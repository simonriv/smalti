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

    /// F4 C8: the bundled `swift` spec gives `swift test` and its `--filter` and `--skip-build` options.
    @Test func swiftTestHasFilterAndSkipBuildOptions() async throws {
        let swift = try #require(await specs().spec(for: "swift"))
        let test = try #require(swift.subcommands.first { $0.name.contains("test") })

        let options = Set(test.options.flatMap(\.names))

        #expect(options.isSuperset(of: ["--filter", "--skip-build"]))
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

    // Block 2 review I1: JS errors after loading reach CompletionError.
    @Test func postProcessThrowIsReported() async throws {
        try writeUserSpec(
            "pthrow",
            "export default { name: \"pthrow\", args: { generators: { script: [\"true\"], postProcess: () => { throw new Error(\"boom\") } } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "pthrow")?.args.first?.generators.first)

        await #expect(throws: CompletionError.self) {
            try await specs.generate(generator, tokens: ["pthrow", ""], in: "/tmp")
        }
        #expect(await specs.lastError?.cause.contains("boom") == true)
    }

    @Test func customSyncThrowIsReported() async throws {
        try writeUserSpec(
            "cthrow",
            "export default { name: \"cthrow\", args: { generators: { custom: () => { throw new Error(\"bad\") } } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "cthrow")?.args.first?.generators.first)

        await #expect(throws: CompletionError.self) {
            try await specs.generate(generator, tokens: ["cthrow", ""], in: "/tmp")
        }
    }

    @Test func thenableCallingBackTwiceResumesOnce() async throws {
        try writeUserSpec(
            "twice",
            "export default { name: \"twice\", args: { generators: { custom: () => ({ then(ok) { ok([{ name: \"a\" }]); ok([{ name: \"b\" }]); } }) } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "twice")?.args.first?.generators.first)

        #expect(try await specs.generate(generator, tokens: ["twice", ""], in: "/tmp").map(\.name) == ["a"])
    }

    // Block 2 review I2: a script built from the tokens is cached per script, not per generator.
    @Test func scriptFromTokensIsCachedPerScript() async throws {
        try writeUserSpec(
            "echoer",
            "export default { name: \"echoer\", args: { generators: { script: (tokens) => [\"echo\", tokens[tokens.length - 1]] } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "echoer")?.args.first?.generators.first)

        let first = try await specs.generate(generator, tokens: ["echoer", "nginx"], in: "/tmp")
        let second = try await specs.generate(generator, tokens: ["echoer", "redis"], in: "/tmp")

        #expect(first.map(\.name) == ["nginx"])
        #expect(second.map(\.name) == ["redis"])
    }

    @Test func customGeneratorIsCachedPerTokens() async throws {
        try writeUserSpec(
            "ctok",
            "export default { name: \"ctok\", args: { generators: { custom: async (t) => [{ name: t[t.length - 1] }] } } };"
        )
        let specs = specs()
        let generator = try #require(await specs.spec(for: "ctok")?.args.first?.generators.first)

        _ = try await specs.generate(generator, tokens: ["ctok", "a"], in: "/tmp")

        #expect(try await specs.generate(generator, tokens: ["ctok", "b"], in: "/tmp").map(\.name) == ["b"])
    }

    // Block 2 review I3: Fig path generators answer relative to the typed folder (getQueryTerm).
    @Test func cdDescendsIntoTypedFolder() async throws {
        let folder = temp.appending(path: "descend")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Projects/smalti"), withIntermediateDirectories: true)
        let specs = specs()
        let generator = try #require(await specs.spec(for: "cd")?.args.first?.generators.first)
        let path = folder.path(percentEncoded: false)

        _ = try await specs.generate(generator, tokens: ["cd", ""], in: path)
        let inside = try await specs.generate(generator, tokens: ["cd", "Projects/"], in: path).map(\.name)
        let partial = try await specs.generate(generator, tokens: ["cd", "Projects/sm"], in: path).map(\.name)

        #expect(inside.contains("Projects/smalti/"))
        #expect(partial.contains("Projects/smalti/"))
    }

    // Block 2 review m2: a generator that never settles fails within the timeout.
    @Test func neverSettlingGeneratorTimesOut() async throws {
        try writeUserSpec(
            "pending",
            "export default { name: \"pending\", args: { generators: { custom: () => new Promise(() => {}) } } };")
        let specs = specs(timeout: .milliseconds(200))
        let generator = try #require(await specs.spec(for: "pending")?.args.first?.generators.first)
        let started = Date()

        await #expect(throws: CompletionError.self) {
            try await specs.generate(generator, tokens: ["pending", ""], in: "/tmp")
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    // Block 2 review m3: output is kept when a background child holds the pipe open.
    @Test func outputSurvivesABackgroundChild() async throws {
        let runner = GeneratorRunner(timeout: .seconds(2))

        let output = try await runner.run(shell: "echo hi; sleep 5 &", in: "/tmp")

        #expect(output.stdout == "hi\n")
    }

    // Block 2 review m5: a bare `~` lists the home folder; results are capped.
    @Test func bareTildeListsHome() async throws {
        let names = await specs().paths(matching: "~", in: "/tmp", foldersOnly: true).map(\.name)

        #expect(!names.isEmpty)
        #expect(names.allSatisfy { $0.hasPrefix("~/") })
    }

    @Test func pathListingIsCapped() async throws {
        let folder = temp.appending(path: "many")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<(PathListingLimits.maximum + 20) {
            FileManager.default.createFile(
                atPath: folder.appending(path: "f\(index)").path(percentEncoded: false), contents: nil)
        }

        #expect(
            await specs().paths(matching: "", in: folder.path(percentEncoded: false), foldersOnly: false).count
                == PathListingLimits.maximum)
    }

    // Block 2 review m6: editing a user spec takes effect; a broken one falls back to the bundled spec.
    @Test func editedUserSpecIsReloaded() async throws {
        try writeUserSpec("mine", "export default { name: \"mine\", subcommands: [{ name: \"one\" }] };")
        let specs = specs()
        _ = await specs.spec(for: "mine")
        try writeUserSpec("mine", "export default { name: \"mine\", subcommands: [{ name: \"two\" }] };")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: userSpecs.appending(path: "mine.js").path(percentEncoded: false))

        #expect(await specs.spec(for: "mine")?.subcommands.map(\.name) == [["two"]])
    }

    @Test func brokenUserSpecFallsBackToBundled() async throws {
        try writeUserSpec("git", "export default { name: ")

        let git = await specs().spec(for: "git")

        #expect(git?.subcommands.contains { $0.name.contains("checkout") } == true)
    }

    // Block 2 review m7: the command name never escapes the completions folder.
    @Test func commandNamesWithPathsAreRejected() async throws {
        try FileManager.default.createDirectory(at: userSpecs, withIntermediateDirectories: true)
        try "export default { name: \"evil\" };".write(
            to: temp.appending(path: "evil.js"), atomically: true, encoding: .utf8)
        let specs = specs()

        #expect(await specs.spec(for: "../evil") == nil)
        #expect(await specs.spec(for: ".hidden") == nil)
    }
}
