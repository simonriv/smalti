import AppKit
import Foundation
import GhosttyKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// C4 (F4): "the cursor is at the shell prompt" comes from libghostty's OSC 133 state, through
/// `ghostty_surface_needs_confirm_quit` with `confirm-close-surface = true` (spike `spike/f4-prompt-overlay`).
/// The shell is `zsh -d` with Ghostty's integration chained to an empty ZDOTDIR: never the user's files.
@MainActor
@Suite("Prompt state", .serialized)
struct PromptStateTests {
    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-prompt-\(UUID())")
    private let runtime: GhosttyRuntime
    private let zdotdir: URL

    init() throws {
        try TestGhostty.initialize()
        zdotdir = work.appending(path: "zdotdir")
        try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        try "PS1='p %# '\nHISTFILE=\(work.path(percentEncoded: false))/hist\n".write(
            to: zdotdir.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: work.appending(path: "g.conf"))
        runtime = try GhosttyRuntime(config: config)
    }

    /// The view and the window that holds it; the runtime lives in the suite. Close it at the end of each test.
    @MainActor
    private final class Pane {
        let view: GhosttySurfaceView
        let window: NSWindow

        init(view: GhosttySurfaceView, window: NSWindow) {
            self.view = view
            self.window = window
        }

        func close() {
            view.shutDown()
            window.close()
        }
    }

    private func openPane() throws -> Pane {
        let spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -d"),
            environment: ["GHOSTTY_ZSH_ZDOTDIR": zdotdir.path(percentEncoded: false), "SMALTI": "1"])
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return Pane(view: view, window: window)
    }

    private func wait(_ condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return condition()
    }

    private func type(_ text: String, into view: GhosttySurfaceView) throws {
        let surface = try #require(view.surface)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        text.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func pressReturn(in view: GhosttySurfaceView) throws {
        let surface = try #require(view.surface)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.keycode = 0x24
        _ = ghostty_surface_key(surface, key)
        key.action = GHOSTTY_ACTION_RELEASE
        _ = ghostty_surface_key(surface, key)
    }

    private func run(_ command: String, in view: GhosttySurfaceView) throws {
        try type(command, into: view)
        try pressReturn(in: view)
    }

    @Test func promptAtFirstPromptAndWhileTyping() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view

        #expect(wait { view.isAtPrompt })
        try type("echo hol", into: view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(view.isAtPrompt)
    }

    @Test func promptInContinuationPS2() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })

        try run("echo \"a", in: view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        #expect(view.isAtPrompt)
    }

    @Test func notPromptDuringCommand() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })

        try run("sleep 1", in: view)

        #expect(wait { !view.isAtPrompt })
        #expect(wait { view.isAtPrompt })
    }

    @Test func notPromptInsideRead() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })

        try run("read x", in: view)

        #expect(wait { !view.isAtPrompt })
    }

    @Test func notPromptOnAlternateScreen() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })

        try run("printf '\\e[?1049h'; sleep 2", in: view)

        #expect(wait { !view.isAtPrompt })
    }

    @Test func notPromptAfterProcessExited() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })

        try run("exit", in: view)

        #expect(wait { !view.isAtPrompt })
    }

    @Test func cursorCellMatchesTypedColumns() throws {
        let pane = try openPane()
        defer { pane.close() }
        let view = pane.view
        #expect(wait { view.isAtPrompt })
        let before = try #require(view.cursorCell)

        try type("abcd", into: view)

        #expect(wait { (view.cursorCell?.origin.x ?? 0) > before.origin.x })
        let after = try #require(view.cursorCell)
        #expect(abs((after.origin.x - before.origin.x) - 4 * after.size.width) < 0.5)
        #expect(after.size.height > after.size.width)
    }
}
