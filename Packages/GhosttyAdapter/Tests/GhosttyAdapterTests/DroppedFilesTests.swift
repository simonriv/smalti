import AppKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

@Suite("Dropped files")
struct DroppedFilesTests {
    @Test func escapesSpacesAndShellCharacters() {
        let text = DroppedFiles.pasteText(for: [URL(filePath: "/tmp/mi captura (1).png")])

        #expect(text == #"/tmp/mi\ captura\ \(1\).png"#)
    }

    @Test func escapesQuotesAndOtherMetacharacters() {
        let text = DroppedFiles.pasteText(for: [URL(filePath: #"/tmp/a'b"c&d;e|f<g>h*i?j$k`l.png"#)])

        #expect(text == #"/tmp/a\'b\"c\&d\;e\|f\<g\>h\*i\?j\$k\`l.png"#)
    }

    @Test func escapesTabsLikeGhostty() {
        #expect(DroppedFiles.pasteText(for: [URL(filePath: "/tmp/a\tb.png")]) == "/tmp/a\\\tb.png")
    }

    @Test func joinsSeveralFilesWithSpaces() {
        let text = DroppedFiles.pasteText(for: [URL(filePath: "/tmp/a.png"), URL(filePath: "/tmp/b.png")])

        #expect(text == "/tmp/a.png /tmp/b.png")
    }

    @Test func nothingDroppedPastesNothing() {
        #expect(DroppedFiles.pasteText(for: []).isEmpty)
    }
}

/// C17: a dropped image reaches the program as a bracketed paste when the program asks for it (Claude Code does),
/// so it is attached rather than typed.
@MainActor
@Suite("Dropped files on a surface", .serialized)
struct DroppedFilesSurfaceTests {
    @Test func dropPastesBracketedWhenProgramAsksForIt() async throws {
        try TestGhostty.initialize()
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-drop-\(UUID()).conf"))
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config, texts: .spanish))
        let output = FileManager.default.temporaryDirectory.appending(path: "smalti-drop-\(UUID()).txt")
        let script = #"printf '\033[?2004h'; stty raw -echo; dd bs=1 count=40 2>/dev/null | od -c > "$OUT"; sleep 5"#
        let pane = PaneID()
        try engine.open(
            TerminalSessionSpec(
                workingDirectory: try WorkingDirectory(path: "/tmp"),
                command: .custom("/bin/sh -c '\(script.replacingOccurrences(of: "'", with: #"'\''"#))'"),
                environment: ["OUT": output.path(percentEncoded: false)]), as: pane)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        try await Task.sleep(for: .milliseconds(500))

        view.paste(dropped: [URL(filePath: "/tmp/captura de prueba.png")])

        var dump = ""
        for _ in 0..<60 where !dump.contains("~") {
            try await Task.sleep(for: .milliseconds(50))
            dump = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        }
        #expect(dump.contains("033   [   2   0   0   ~"))
        #expect(dump.contains("p   r   u   e"))
    }
}
