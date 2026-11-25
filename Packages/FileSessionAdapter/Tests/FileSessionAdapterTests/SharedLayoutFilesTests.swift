import FileSessionAdapter
import Foundation
import SmaltiCore
import Testing

@MainActor
@Suite("Shared layout files")
struct SharedLayoutFilesTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-shared-\(UUID())")
    private let files = SharedLayoutFiles()
    private let layout = SharedLayout(
        smaltiLayout: 1, name: "solen-dev", root: "~/Projects/solen", layout: "columns", focused: 0,
        tree: .split(axis: .sideBySide, ratio: 0.5, first: .leaf(index: 0), second: .leaf(index: 1)),
        panes: [
            SharedPane(directory: ".", command: ["pnpm", "dev"]),
            SharedPane(directory: "api", harness: .claude, editor: SharedEditor(file: "src/a.ts", line: 42)),
        ])

    private var file: URL { directory.appending(path: "solen-dev.smalti-layout.json") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func roundTripsLayout() throws {
        try files.write(layout, to: file)

        #expect(try files.read(from: file) == layout)
    }

    @Test func writesSortedPrettyJSON() throws {
        try files.write(layout, to: file)

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("{\n"))
        #expect(text.contains(#""directory" : "api""#))
        let keys = ["focused", "layout", "name", "panes", "root", "smaltiLayout", "tree"]
        let positions = keys.compactMap { text.range(of: "\n  \"\($0)\"")?.lowerBound }
        #expect(positions == positions.sorted())
        #expect(positions.count == keys.count)
        #expect(!text.contains("\\/"))
    }

    @Test func rejectsOversizedFileWithoutReadingIt() throws {
        try Data(repeating: UInt8(ascii: " "), count: SharedLayout.maximumBytes + 1).write(to: file)

        #expect(throws: LayoutFileError.invalid(.tooLarge(bytes: SharedLayout.maximumBytes + 1))) {
            try files.read(from: file)
        }
    }

    @Test func acceptsAFileAtTheLimit() throws {
        let json = try JSONEncoder().encode(layout)
        var padded = json
        padded.append(Data(repeating: UInt8(ascii: " "), count: SharedLayout.maximumBytes - json.count))
        try padded.write(to: file)

        #expect(try files.read(from: file) == layout)
    }

    @Test func rejectsNonJSON() throws {
        try Data("hola".utf8).write(to: file)

        do {
            _ = try files.read(from: file)
            Issue.record("non-JSON was read")
        } catch {
            guard case .invalid(.notJSON) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    @Test func missingFileIsUnreadable() {
        do {
            _ = try files.read(from: directory.appending(path: "nada.json"))
            Issue.record("a missing file was read")
        } catch {
            guard case .unreadable = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    @Test func unwritableDirectoryIsTyped() {
        do {
            try files.write(layout, to: URL(filePath: "/nonexistent-\(UUID())/x.smalti-layout.json"))
            Issue.record("wrote into a missing directory")
        } catch {
            guard case .unwritable = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    /// A device or a FIFO reports size 0 and could be read without end (`/dev/zero`): only regular files are read.
    @Test(.timeLimit(.minutes(1)))
    func rejectsWhatIsNotARegularFile() throws {
        do {
            _ = try files.read(from: URL(filePath: "/dev/null"))
            Issue.record("a FIFO was read")
        } catch {
            guard case .unreadable = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }
}
