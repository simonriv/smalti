import Darwin
import Foundation
import ProjectContextAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("FileSystemPathFacts")
struct FileSystemPathFactsTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "smalti-paths-\(UUID())")
    private var rootPath: String { root.path(percentEncoded: false) }

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeSample() throws -> PathFactsSample {
        let sample = PathFactsSample.standard(root: rootPath)
        let files = FileManager.default
        try Data("x".utf8).write(to: URL(filePath: sample.file))
        try files.createDirectory(atPath: sample.directory, withIntermediateDirectories: true)
        try files.createSymbolicLink(atPath: sample.linkToFile, withDestinationPath: sample.file)
        try files.createSymbolicLink(atPath: sample.linkToLink, withDestinationPath: sample.linkToFile)
        return sample
    }

    @Test func honoursPathFactsContract() async throws {
        try await PathFactsContract.verify { (FileSystemPathFacts(), try makeSample()) }
    }

    @Test func fifoIsFileWithoutBlocking() async throws {
        let fifo = rootPath + "/pipe"
        #expect(mkfifo(fifo, 0o600) == 0)
        let start = ContinuousClock.now

        let kind = await FileSystemPathFacts().kind(of: fifo)

        #expect(kind == .file)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }

    @Test func linkToDirectoryIsDirectory() async throws {
        let sample = try makeSample()
        let link = rootPath + "/dirlink"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sample.directory)

        #expect(await FileSystemPathFacts().kind(of: link) == .directory)
    }

    @Test func danglingLinkIsNil() async throws {
        let link = rootPath + "/dangling"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: rootPath + "/nowhere")

        #expect(await FileSystemPathFacts().kind(of: link) == nil)
    }

    @Test func unreadableParentGivesNil() async throws {
        let locked = root.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: locked.appending(path: "inside"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        }

        #expect(await FileSystemPathFacts().kind(of: locked.path(percentEncoded: false) + "/inside") == nil)
    }
}
