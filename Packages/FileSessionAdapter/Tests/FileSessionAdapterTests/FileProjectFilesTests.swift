import FileSessionAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("FileProjectFiles (F8.5)")
struct FileProjectFilesTests {
    private let files = FileProjectFiles()

    private func repo() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "smalti-project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false).trimmingSuffix("/") }

    private let layout = SharedLayout(
        smaltiLayout: 1, name: "rizaria", root: ".", layout: "dwindle", focused: 0, tree: .leaf(index: 0),
        panes: [SharedPane(directory: ".", command: ["npm", "run", "dev"])])

    private func writeRaw(_ text: String, in root: URL) throws {
        let folder = root.appending(path: ".smalti")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appending(path: "layout.json"))
    }

    @Test func writtenThenReadIsTheSameLayoutAndFingerprint() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }

        let written = try files.write(layout, to: path(root))
        let read = try files.layout(at: path(root))

        #expect(read.layout == layout)
        #expect(read.fingerprint == written)
        #expect(written.count == 64)
        #expect(files.hasLayout(in: path(root)))
    }

    @Test func oneByteChangesTheFingerprint() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        let json = #"{"smaltiLayout":1,"name":"a","root":".","layout":"dwindle","panes":[{"directory":"."}]}"#
        try writeRaw(json, in: root)
        let first = try files.layout(at: path(root)).fingerprint

        try writeRaw(json + " ", in: root)

        #expect(try files.layout(at: path(root)).fingerprint != first)
    }

    @Test func theFingerprintIsTheSHA256OfTheBytes() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRaw(
            #"{"smaltiLayout":1,"name":"a","root":".","layout":"dwindle","panes":[{"directory":"."}]}"#, in: root)

        // shasum -a 256 of the exact bytes above.
        #expect(
            try files.layout(at: path(root)).fingerprint
                == "6e0449a5f23a1dcb93c7a336815c8e69afb236ee3fcf08cc7e290724329a3399")
    }

    @Test func aMissingFileIsMissing() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!files.hasLayout(in: path(root)))
        #expect(throws: ProjectFileError.missing(root: path(root))) { try files.layout(at: path(root)) }
    }

    @Test func anInvalidProjectIsInvalid() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRaw(
            #"{"smaltiLayout":1,"name":"a","root":"~/x","layout":"dwindle","panes":[{"directory":"."}]}"#, in: root)

        #expect(throws: ProjectFileError.invalid(.invalidRoot("~/x"))) { try files.layout(at: path(root)) }
    }

    @Test func notJSONIsInvalid() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRaw("hola", in: root)

        #expect(throws: ProjectFileError.invalid(.notJSON(.invalid))) { try files.layout(at: path(root)) }
    }

    @Test func aFileOverTheLimitIsNotRead() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRaw(String(repeating: " ", count: SharedLayout.maximumBytes + 1), in: root)

        #expect(throws: ProjectFileError.invalid(.tooLarge(bytes: SharedLayout.maximumBytes + 1))) {
            try files.layout(at: path(root))
        }
    }

    @Test func repositoryRootsAreFoldersOrFilesNamedGit() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        let submodule = root.appending(path: "sub")
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try Data("gitdir: ../.git/modules/sub\n".utf8).write(to: submodule.appending(path: ".git"))

        #expect(files.isRepositoryRoot(path(root)))
        #expect(files.isRepositoryRoot(path(submodule)))
        #expect(!files.isRepositoryRoot(path(root.appending(path: "nothing"))))
    }

    @Test func realPathResolvesLinks() throws {
        let root = try repo()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(files.realPath(path(link)) == files.realPath(path(real)))
        #expect(files.realPath(path(link)).hasSuffix("/real"))
        #expect(files.realPath("/no/such/path") == "/no/such/path")
    }

    @Test func aWriteThatCannotHappenIsTyped() throws {
        let root = try repo()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path(root))
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path(root))

        #expect {
            try files.write(layout, to: path(root))
        } throws: { error in
            guard case .unwritable = error as? ProjectFileError else { return false }
            return true
        }
    }
}

@Suite("FileProjectRecords (F8.5)")
struct FileProjectRecordsTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-projects-\(UUID().uuidString)")
    }

    @Test func followsTheContract() throws {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }

        try ProjectRecordsContract.verify { FileProjectRecords(directory: base) }
    }

    @Test func theInMemoryFakeFollowsTheContractToo() throws {
        try ProjectRecordsContract.verify { InMemoryProjectRecords() }
    }

    @Test func writesAVersionedOwnerOnlyFile() throws {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }

        try FileProjectRecords(directory: base).replace(with: [
            ProjectRecord(root: "/p/a", name: "a", lastOpened: Date(timeIntervalSince1970: 1), approval: nil)
        ])

        let file = base.appending(path: "projects.json")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"version\""))
        let permissions =
            try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[
                .posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func anUnreadableOrNewerFileListsNothing() throws {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appending(path: "projects.json")

        try Data("nope".utf8).write(to: file)
        #expect(FileProjectRecords(directory: base).all().isEmpty)

        try Data(#"{"version":2,"projects":[]}"#.utf8).write(to: file)
        #expect(FileProjectRecords(directory: base).all().isEmpty)
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
