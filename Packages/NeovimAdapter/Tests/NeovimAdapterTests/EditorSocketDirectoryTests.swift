import Foundation
import Testing

@testable import NeovimAdapter

/// Final review: the socket folder lives in `/tmp`, so Smalti only uses one it owns, as a real folder, mode 0700.
@Suite("Editor socket directory")
struct EditorSocketDirectoryTests {
    private let base = "/private/tmp/smalti-sockdir-test-\(UUID().uuidString.prefix(8))"

    private func mode(_ path: String) throws -> Int {
        try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
    }

    @Test func missingFolderIsCreatedPrivate() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }

        let path = EditorSocketDirectory.prepare(base)

        #expect(path == base)
        #expect(try mode(path) == 0o700)
    }

    @Test func ownFolderIsMadePrivate() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base)

        let path = EditorSocketDirectory.prepare(base)

        #expect(path == base)
        #expect(try mode(path) == 0o700)
    }

    @Test func symlinkIsNotTrusted() throws {
        let target = base + "-target"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: base, withDestinationPath: target)
        let path = EditorSocketDirectory.prepare(base)
        defer {
            for item in [base, target, path] { try? FileManager.default.removeItem(atPath: item) }
        }

        #expect(path != base)
        #expect(path.hasPrefix("/private/tmp/smalti-"))
        #expect(try mode(path) == 0o700)
    }
}
