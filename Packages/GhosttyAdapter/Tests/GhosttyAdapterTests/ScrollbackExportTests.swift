import AppKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F2 C7: a pane's scrollback is exported with its colours (libghostty `write_screen_file:open,vt`, whose
/// OPEN_URL the adapter keeps instead of opening), or as plain text when that fails.
@MainActor
@Suite("Scrollback export", .serialized)
struct ScrollbackExportTests {
    private let engine: GhosttyTerminalEngine
    private let spec: TerminalSessionSpec

    init() throws {
        try TestGhostty.initialize()
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-scrollback-\(UUID()).conf"))
        engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config, texts: .spanish))
        spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"),
            command: .custom(#"/bin/zsh -f -c 'printf "\033[31mrojo-smalti\033[0m\n"; sleep 30'"#))
    }

    /// Waits until the pane printed its marker, so the export has something to read.
    private func openPrinting() async throws -> PaneID {
        let pane = PaneID()
        try engine.open(spec, as: pane)
        for _ in 0..<60 {
            if (try? engine.scrollback(of: pane, lastLines: 100))?.text.contains("rojo-smalti") == true { return pane }
            try await Task.sleep(for: .milliseconds(50))
        }
        return pane
    }

    @Test func exportReturnsVTWithColors() async throws {
        let pane = try await openPrinting()
        defer { engine.close(pane) }

        let scrollback = try engine.scrollback(of: pane, lastLines: 10_000)

        #expect(scrollback.format == .vt)
        #expect(scrollback.text.contains("rojo-smalti"))
        // libghostty resolves palette colours to true colour: ANSI red is Obsidiana's #f7768e.
        #expect(scrollback.text.contains("\u{1B}[38;2;247;118;142mrojo-smalti"))
    }

    @Test func exportFallsBackToPlainWhenVTFails() async throws {
        let pane = try await openPrinting()
        defer { engine.close(pane) }
        engine.exportsVT = false

        let scrollback = try engine.scrollback(of: pane, lastLines: 10_000)

        #expect(scrollback.format == .plain)
        #expect(scrollback.text.contains("rojo-smalti"))
    }

    @Test func exportDoesNotLeaveTheTemporaryFile() async throws {
        let pane = try await openPrinting()
        defer { engine.close(pane) }

        _ = try engine.scrollback(of: pane, lastLines: 10_000)

        #expect(ScrollbackExporter.lastExportedFile.map { FileManager.default.fileExists(atPath: $0) } == false)
    }

    @Test func discardRemovesOnlyTheFileAndItsFolderWhenEmpty() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "smalti-discard-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let screen = folder.appending(path: "screen.txt")
        let neighbour = folder.appending(path: "otro.txt")
        try Data("x".utf8).write(to: screen)
        try Data("y".utf8).write(to: neighbour)

        ScrollbackExporter.discard(screen.path(percentEncoded: false))

        #expect(!FileManager.default.fileExists(atPath: screen.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: neighbour.path(percentEncoded: false)))
    }

    /// VoiceOver and UI tests read the screen as the surface's accessibility value.
    @Test func surfaceExposesItsScreenText() async throws {
        let pane = try await openPrinting()
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        #expect((view.accessibilityValue() as? String)?.contains("rojo-smalti") == true)
        #expect(view.accessibilityRole() == .textArea)
    }

    /// Accessibility reads what is on screen, not the whole scrollback.
    @Test func accessibilityReadsOnlyTheViewport() async throws {
        let pane = PaneID()
        try engine.open(
            TerminalSessionSpec(
                workingDirectory: try WorkingDirectory(path: "/tmp"),
                command: .custom(#"/bin/zsh -f -c 'for i in {1..400}; do echo linea-$i; done; sleep 30'"#)), as: pane)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        for _ in 0..<60 where (view.accessibilityValue() as? String)?.contains("linea-400") != true {
            try await Task.sleep(for: .milliseconds(50))
        }

        let text = view.accessibilityValue() as? String ?? ""

        #expect(text.contains("linea-400"))
        #expect(!text.contains("linea-1\n"))
    }

    @Test func unknownPaneIsUnavailable() {
        #expect(throws: ScrollbackError.self) { try engine.scrollback(of: PaneID(), lastLines: 10) }
    }
}
