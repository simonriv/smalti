import SmaltiCore
import Testing

@Suite("WorkingDirectory")
struct WorkingDirectoryTests {
    @Test func acceptsAbsolutePath() throws {
        #expect(try WorkingDirectory(path: "/tmp").path == "/tmp")
    }

    @Test(arguments: ["tmp", ""])
    func rejectsNonAbsolutePath(_ path: String) {
        #expect(throws: WorkingDirectoryError.notAbsolute(path: path)) {
            try WorkingDirectory(path: path)
        }
    }

    @Test func dropsTrailingSlash() throws {
        #expect(try WorkingDirectory(path: "/Users/x/").path == "/Users/x")
    }

    @Test func keepsRootAsIs() throws {
        #expect(try WorkingDirectory(path: "/").path == "/")
    }

    @Test func abbreviatesHomeWithTilde() throws {
        let home = try WorkingDirectory(path: "/Users/s")
        let directory = try WorkingDirectory(path: "/Users/s/dev/x")

        #expect(directory.abbreviated(home: home) == "~/dev/x")
    }

    @Test func homeItselfIsTilde() throws {
        let home = try WorkingDirectory(path: "/Users/s")

        #expect(home.abbreviated(home: home) == "~")
    }

    @Test func doesNotAbbreviateSiblingWithSamePrefix() throws {
        let home = try WorkingDirectory(path: "/Users/s")
        let sibling = try WorkingDirectory(path: "/Users/sam/dev")

        #expect(sibling.abbreviated(home: home) == "/Users/sam/dev")
    }

    @Test func lastComponentIsTheFolderName() throws {
        #expect(try WorkingDirectory(path: "/Users/s/dev/x").lastComponent == "x")
        #expect(try WorkingDirectory(path: "/").lastComponent == "/")
    }
}
