import Foundation
import ProjectContextAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// A clock the tests move by hand; only touched from the test's own task.
final class ContextClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite("FileProjectContext")
struct FileProjectContextTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "smalti-project-\(UUID())")
    private var rootPath: String { root.path(percentEncoded: false) }

    private func write(_ text: String, to relative: String) throws {
        let file = root.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func makeRepository(branch: String = "main") throws {
        try write("ref: refs/heads/\(branch)\n", to: ".git/HEAD")
        try write("abc\n", to: ".git/refs/heads/main")
        try write("abc\n", to: ".git/refs/heads/feature/x")
        try write("# pack-refs with: peeled\nabc refs/heads/old\ndef refs/tags/v1\n", to: ".git/packed-refs")
    }

    @Test func fulfillsTheContract() async {
        await ProjectContextContract.verify { _ in FileProjectContext() }
    }

    @Test func readsScriptsFromNearestPackageJSON() async throws {
        try write(#"{"scripts":{"outer":"x"}}"#, to: "package.json")
        try write(#"{"name":"web","scripts":{"dev":"vite","test":"vitest"}}"#, to: "web/package.json")
        try FileManager.default.createDirectory(at: root.appending(path: "web/src"), withIntermediateDirectories: true)

        let snapshot = await FileProjectContext().snapshot(of: rootPath + "/web/src")

        #expect(Set(snapshot.scripts) == ["dev", "test"])
    }

    @Test func invalidJSONYieldsNoScripts() async throws {
        try write("{not json", to: "package.json")

        #expect(await FileProjectContext().snapshot(of: rootPath).scripts.isEmpty)
    }

    @Test func readsMakeTargetsSkippingSpecial() async throws {
        try write(
            ".PHONY: build test\nbuild: deps\n\tswift build\ntest:\n\tswift test\n.hidden:\nVAR := 1\n\tnot-a-target:\n",
            to: "Makefile")

        #expect(await FileProjectContext().snapshot(of: rootPath).makeTargets == ["build", "test"])
    }

    @Test func readsBranchAndBranchesIncludingPacked() async throws {
        try makeRepository(branch: "feature/x")

        let snapshot = await FileProjectContext().snapshot(of: rootPath)

        #expect(snapshot.branch == "feature/x")
        #expect(Set(snapshot.branches) == ["main", "feature/x", "old"])
    }

    @Test func detachedHeadHasNoBranch() async throws {
        try makeRepository()
        try write("0123456789abcdef\n", to: ".git/HEAD")

        #expect(await FileProjectContext().snapshot(of: rootPath).branch == nil)
    }

    @Test func followsWorktreeGitdir() async throws {
        try makeRepository()
        try write("ref: refs/heads/feature/x\n", to: ".git/worktrees/wt/HEAD")
        try write("../..\n", to: ".git/worktrees/wt/commondir")
        try write("gitdir: \(rootPath)/.git/worktrees/wt\n", to: "wt/.git")

        let snapshot = await FileProjectContext().snapshot(of: rootPath + "/wt")

        #expect(snapshot.branch == "feature/x")
        #expect(snapshot.branches.contains("main"))
    }

    // Review m11 (block 1): the push recovery needs to know whether the branch has an upstream.
    @Test func upstreamReadFromGitConfig() async throws {
        try makeRepository()
        try write(
            "[core]\n\tbare = false\n[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n",
            to: ".git/config")

        #expect(await FileProjectContext().snapshot(of: rootPath).hasUpstream)
    }

    @Test func branchWithoutConfigHasNoUpstream() async throws {
        try makeRepository(branch: "feature/x")
        try write("[branch \"main\"]\n\tremote = origin\n", to: ".git/config")

        #expect(await !FileProjectContext().snapshot(of: rootPath).hasUpstream)
    }

    @Test func cacheRefreshesOnMtimeChange() async throws {
        try write(#"{"scripts":{"dev":"x"}}"#, to: "package.json")
        let clock = ContextClock()
        let context = FileProjectContext(clock: { clock.now })
        _ = await context.snapshot(of: rootPath)
        clock.now += FileProjectContext.recheckInterval + 0.1

        try write(#"{"scripts":{"dev":"x","lint":"y"}}"#, to: "package.json")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: rootPath + "/package.json")

        #expect(Set(await context.snapshot(of: rootPath).scripts) == ["dev", "lint"])
    }

    // Block 2 review I4: a big packed-refs (tags after a fetch) parses fast.
    @Test func largePackedRefsParseQuickly() async throws {
        try makeRepository()
        var lines = ["# pack-refs with: peeled"]
        lines.reserveCapacity(200_002)
        for index in 0..<200_000 { lines.append("0123456789abcdef0123456789abcdef01234567 refs/tags/v\(index)") }
        lines.append("0123456789abcdef0123456789abcdef01234567 refs/heads/packed-branch")
        try write(lines.joined(separator: "\n") + "\n", to: ".git/packed-refs")
        let started = Date()

        let snapshot = await FileProjectContext().snapshot(of: rootPath)

        #expect(snapshot.branches.contains("packed-branch"))
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    // Block 2 review m4: within a second, a directory is answered from memory without touching the disk.
    @Test func recentSnapshotIsReusedWithoutRechecking() async throws {
        try write(#"{"scripts":{"dev":"x"}}"#, to: "package.json")
        let clock = ContextClock()
        let context = FileProjectContext(clock: { clock.now })
        _ = await context.snapshot(of: rootPath)

        try FileManager.default.removeItem(at: root.appending(path: "package.json"))
        clock.now += 0.5
        let reused = await context.snapshot(of: rootPath)
        clock.now += 1
        let rechecked = await context.snapshot(of: rootPath)

        #expect(reused.scripts == ["dev"])
        #expect(rechecked.scripts.isEmpty)
    }
}
