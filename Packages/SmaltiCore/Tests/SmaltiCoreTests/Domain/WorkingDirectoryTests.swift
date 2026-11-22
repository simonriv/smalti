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
}
