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

        #expect(TerminalSize.metrics(of: secondary) == CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16))
    }

    @Test func terminalWithoutPixelsGivesNoMetrics() throws {
        let (main, secondary) = try pty(columns: 80, rows: 24, width: 0, height: 0)
        defer {
            close(main)
            close(secondary)
        }

        #expect(TerminalSize.metrics(of: secondary) == nil)
    }

    @Test func pipeGivesNoMetrics() {
        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        defer { ends.forEach { close($0) } }

        #expect(TerminalSize.metrics(of: ends[1]) == nil)
    }
}
