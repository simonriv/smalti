import Darwin
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@testable import smalti

/// Spec F5.5: `smalti img [carpeta|archivos…]`.
@Suite("smalti img")
struct ImageCommandTests {
    final class RecordingTerminal: CommandTerminal, @unchecked Sendable {
        let metrics: CellMetrics?
        var written = ""
        var errors = ""

        init(metrics: CellMetrics? = nil) {
            self.metrics = metrics
        }

        func write(_ text: String) { written += text }
        func writeError(_ text: String) { errors += text }
    }

    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "smalti-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["b.png", "a.jpg", ".hidden.png", "notes.md"] {
            try Data().write(to: folder.appending(path: name))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
    }

    private func listing(_ arguments: [String]) throws(ImageArgumentError) -> ImageListing {
        try ImageArguments.listing(arguments, currentDirectory: folder.path)
    }

    @Test func noArgumentsUsesCurrentDirectory() throws {
        let listing = try listing([])

        #expect(Set(listing.images) == [folder.appending(path: "b.png").path, folder.appending(path: "a.jpg").path])
        #expect(listing.source == ".")
    }

    @Test func folderSkipsHiddenAndCountsNonImages() throws {
        let listing = try listing([folder.path])

        #expect(listing.images.count == 2)
        #expect(listing.skipped == 1)
    }

    @Test func hiddenFileIsKeptWhenNamed() throws {
        let listing = try listing([".hidden.png", "notes.md"])

        #expect(listing.images == [folder.appending(path: ".hidden.png").path])
        #expect(listing.skipped == 1)
    }

    @Test func missingPathFails() {
        #expect(throws: ImageArgumentError.missing("nada")) { try listing(["nada"]) }
    }

    @Test func missingPathMessageAndCode() async {
        let terminal = RecordingTerminal()

        let code = await ImageCommand.run(["nada"], in: folder.path, terminal: terminal)

        #expect(code == 1)
        #expect(terminal.errors == "No existe: nada\n")
        #expect(terminal.written.isEmpty)
    }

    @Test func helpPrintsUsage() async {
        let terminal = RecordingTerminal()

        let code = await ImageCommand.run(["--help"], in: folder.path, terminal: terminal)

        #expect(code == 0)
        #expect(terminal.written.hasPrefix("uso: smalti img [carpeta | archivos…]"))
    }

    /// Block 3 review I3: a folder that cannot be read is an error, not an empty folder.
    @Test func unreadableFolderFails() async throws {
        let locked = folder.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let terminal = RecordingTerminal()

        let code = await ImageCommand.run(["locked"], in: folder.path, terminal: terminal)

        #expect(code == 1)
        #expect(terminal.errors == "No se pudo leer: locked\n")
    }

    @Test func helpIsFoundAnywhere() async {
        let terminal = RecordingTerminal()

        #expect(await ImageCommand.run([".", "--help"], in: folder.path, terminal: terminal) == 0)
        #expect(terminal.written.hasPrefix("uso: smalti img"))
    }

    @Test func doubleDashEndsOptions() throws {
        try Data().write(to: folder.appending(path: "--help.png"))

        let listing = try listing(["--", "--help.png"])

        #expect(listing.images == [folder.appending(path: "--help.png").path])
    }

    @Test func sameImageTwiceIsListedOnce() throws {
        let listing = try listing([".", "./b.png"])

        #expect(listing.images.count == 2)
    }

    @Test func brokenLinkInFolderCountsAsSkipped() throws {
        try FileManager.default.createSymbolicLink(
            atPath: folder.appending(path: "gone.png").path, withDestinationPath: "/nonexistent/x.png")

        let listing = try listing([])

        // An image name that describes as nothing: the grid counts it as skipped, it never vanishes.
        #expect(listing.images.contains(folder.appending(path: "gone.png").path))
    }

    /// Block 3 review m5: describing thousands of files takes seconds; say so on a terminal.
    @Test func manyFilesAreAnnouncedOnATerminal() async throws {
        let many = folder.appending(path: "many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<501 { try Data().write(to: many.appending(path: "i\(index).png")) }
        let terminal = RecordingTerminal(metrics: CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16))

        _ = await ImageCommand.run(["many"], in: folder.path, terminal: terminal)

        #expect(terminal.errors.hasPrefix("Leyendo 501 archivos…\n"))
    }

    @Test func fewFilesAreNotAnnounced() async throws {
        let terminal = RecordingTerminal(metrics: CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16))

        _ = await ImageCommand.run([], in: folder.path, terminal: terminal)

        #expect(!terminal.errors.contains("Leyendo"))
    }

    @Test func emptyFolderSaysSo() async throws {
        let empty = folder.appending(path: "sub")
        let terminal = RecordingTerminal()

        let code = await ImageCommand.run([empty.path], in: folder.path, terminal: terminal)

        #expect(code == 0)
        #expect(terminal.written == "Sin imágenes en \(empty.path)\n")
    }
}

/// The terminal's size in cells and pixels, from `TIOCGWINSZ`.
@Suite("Terminal size")
struct TerminalSizeTests {
    private func pty(columns: UInt16, rows: UInt16, width: UInt16, height: UInt16) throws -> (Int32, Int32) {
        var main: Int32 = 0
        var secondary: Int32 = 0
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: width, ws_ypixel: height)
        #expect(openpty(&main, &secondary, nil, nil, &size) == 0)
        return (main, secondary)
    }

    @Test func ptyGivesCellMetrics() throws {
        let (main, secondary) = try pty(columns: 80, rows: 24, width: 640, height: 384)
        defer {
            close(main)
            close(secondary)
        }

        let metrics = TerminalSize.metrics(of: secondary, environment: [:])

        #expect(metrics?.columns == 80 && metrics?.cellWidth == 8 && metrics?.cellHeight == 16)
        #expect(metrics?.visibleRows == 24)
    }

    /// Block 3 review I2: tmux drops kitty graphics unless passthrough is set up: inside it, the plain list.
    @Test func insideTmuxGivesNoMetrics() throws {
        let (main, secondary) = try pty(columns: 80, rows: 24, width: 640, height: 384)
        defer {
            close(main)
            close(secondary)
        }

        #expect(TerminalSize.metrics(of: secondary, environment: ["TMUX": "/tmp/tmux-501/default,1,0"]) == nil)
    }

    @Test func terminalWithoutPixelsGivesNoMetrics() throws {
        let (main, secondary) = try pty(columns: 80, rows: 24, width: 0, height: 0)
        defer {
            close(main)
            close(secondary)
        }

        #expect(TerminalSize.metrics(of: secondary, environment: [:]) == nil)
    }

    @Test func pipeGivesNoMetrics() {
        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        defer { ends.forEach { close($0) } }

        #expect(TerminalSize.metrics(of: ends[1], environment: [:]) == nil)
    }
}
