import AppKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F2 C7: a restored pane prints its saved scrollback and the "restaurado" banner before its shell starts, and
/// types its initial command into the shell.
@MainActor
@Suite("Restored surfaces", .serialized)
struct RestoredSurfaceTests {
    private let engine: GhosttyTerminalEngine
    private let tmp: WorkingDirectory
    private let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        try TestGhostty.initialize()
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-restored-\(UUID()).conf"))
        engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        tmp = try WorkingDirectory(path: "/tmp")
    }

    private func screen(of pane: PaneID, containing marker: String) async throws -> String {
        var text = ""
        for _ in 0..<80 {
            engine.exportsVT = false
            text = (try? engine.scrollback(of: pane, lastLines: 1000))?.text ?? ""
            if text.contains(marker) { return text }
            try await Task.sleep(for: .milliseconds(50))
        }
        return text
    }

    @Test func restoredSurfacePrintsScrollbackThenStartsShell() async throws {
        let pane = PaneID()
        let restoration = PaneRestoration(
            scrollback: Scrollback(text: "salida-guardada", format: .plain), restoresHistory: true, savedAt: savedAt)
        try engine.open(
            TerminalSessionSpec(
                workingDirectory: tmp, command: .custom("/bin/zsh -f"), restoration: restoration,
                initialInput: "echo listo-$((40+2))\n"), as: pane)
        defer { engine.close(pane) }

        let text = try await screen(of: pane, containing: "listo-42")

        let saved = text.range(of: "salida-guardada")
        let banner = text.range(of: "restaurado ·")
        let typed = text.range(of: "listo-42")
        #expect(saved != nil && banner != nil && typed != nil)
        if let saved, let banner, let typed {
            #expect(saved.lowerBound < banner.lowerBound)
            #expect(banner.lowerBound < typed.lowerBound)
        }
    }

    @Test func restoreFileIsRemovedAfterStart() async throws {
        let pane = PaneID()
        let restoration = PaneRestoration(
            scrollback: Scrollback(text: "otra-salida", format: .plain), restoresHistory: false, savedAt: savedAt)
        try engine.open(
            TerminalSessionSpec(workingDirectory: tmp, command: .custom("/bin/zsh -f"), restoration: restoration),
            as: pane)
        defer { engine.close(pane) }

        _ = try await screen(of: pane, containing: "restaurado")

        let file = engine.restoreFile(for: pane).path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    @Test func initialInputIsTypedIntoTheShell() async throws {
        let pane = PaneID()
        try engine.open(
            TerminalSessionSpec(
                workingDirectory: tmp, command: .custom("/bin/zsh -f"), initialInput: "echo eco-$((6*7))\n"), as: pane)
        defer { engine.close(pane) }

        #expect(try await screen(of: pane, containing: "eco-42").contains("eco-42"))
    }

    @Test func restoredHistoryIsAnnouncedToTheShell() throws {
        let restoration = PaneRestoration(scrollback: nil, restoresHistory: true, savedAt: savedAt)
        let spec = TerminalSessionSpec(workingDirectory: tmp, command: .custom("/bin/zsh -f"), restoration: restoration)

        let prepared = engine.prepared(spec, for: PaneID())

        #expect(prepared.environment["SMALTI_RESTORE_HISTORY"] == "1")
        #expect(prepared.command == .custom("/bin/zsh -f"))
    }

    /// Spec risk: the launcher must not lose libghostty's zsh integration, which libghostty enables by pointing
    /// `ZDOTDIR` at it; the shell the launcher execs must still see that `ZDOTDIR`.
    @Test func zshIntegrationDirectorySurvivesTheLauncher() async throws {
        let pane = PaneID()
        let restoration = PaneRestoration(
            scrollback: Scrollback(text: "previa", format: .plain), restoresHistory: false, savedAt: savedAt)
        let probe = #"/bin/sh -c 'echo ZD=$ZDOTDIR FIN; sleep 5'"#
        try engine.open(
            TerminalSessionSpec(workingDirectory: tmp, command: .custom(probe), restoration: restoration), as: pane)
        defer { engine.close(pane) }

        let text = try await screen(of: pane, containing: "FIN")

        #expect(text.contains("ZD=\(TestGhostty.resources.path(percentEncoded: false))/shell-integration/zsh FIN"))
        #expect(text.contains("previa"))
    }
}
