import AppKit
import Foundation
import GhosttyKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F4.5 T1: the libghostty v1.4.0 APIs F4.5 relies on, against a real surface (search, binding actions, visible
/// text, secure input, link hover). `zsh -f`: no user files, no integration needed.
@MainActor
@Suite("libghostty APIs for F4.5", .serialized)
struct LibghosttyF45ApiTests {
    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-f45-\(UUID())")
    private let runtime: GhosttyRuntime

    init() throws {
        try TestGhostty.initialize()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: work.appending(path: "g.conf"))
        runtime = try GhosttyRuntime(config: config)
    }

    @MainActor
    private final class Pane {
        let view: GhosttySurfaceView
        let window: NSWindow
        private(set) var received: [TerminalEvent] = []
        private var reader: Task<Void, Never>?

        init(view: GhosttySurfaceView, window: NSWindow) {
            self.view = view
            self.window = window
            reader = Task { @MainActor [weak self] in
                guard let stream = self?.view.events else { return }
                for await event in stream { self?.received.append(event) }
            }
        }

        func close() {
            reader?.cancel()
            view.shutDown()
            window.close()
        }
    }

    private func openPane() throws -> Pane {
        let spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f"),
            environment: ["SMALTI": "1", "PS1": "p%# "])
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return Pane(view: view, window: window)
    }

    /// Async so the main actor is free between checks: libghostty's ticks and the event reader both run on it. It
    /// ticks this suite's app itself: the runtime's wakeups tick only the latest app, another suite's when they run in
    /// parallel, and search results arrive through the tick.
    private func wait(_ condition: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            ghostty_app_tick(runtime.app)
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func run(_ command: String, in view: GhosttySurfaceView) throws {
        let surface = try #require(view.surface)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        command.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
        view.pressReturn()
    }

    private func bind(_ action: String, in view: GhosttySurfaceView) throws -> Bool {
        let surface = try #require(view.surface)
        return ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    private static func isSearchTotal(_ event: TerminalEvent) -> Bool {
        if case .searchTotal = event { true } else { false }
    }

    private static func isSearchTotalOfAtLeastTwo(_ event: TerminalEvent) -> Bool {
        if case .searchTotal(.some(let total)) = event { total >= 2 } else { false }
    }

    private static func isSomeSelection(_ event: TerminalEvent) -> Bool {
        if case .searchSelected(.some) = event { true } else { false }
    }

    private func visible(_ view: GhosttySurfaceView) -> String {
        (view.accessibilityValue() as? String) ?? ""
    }

    @Test func searchReportsTotalAndSelected() async throws {
        let pane = try openPane()
        defer { pane.close() }
        try run("printf 'warn\\nok\\nwarn\\n'", in: pane.view)
        #expect(await wait { visible(pane.view).components(separatedBy: "warn").count >= 4 })

        #expect(try bind("search:warn", in: pane.view))
        // The command line itself also matches, so the total is at least the two output lines.
        #expect(await wait { pane.received.contains(where: Self.isSearchTotalOfAtLeastTwo) })
        #expect(try bind("navigate_search:next", in: pane.view))

        #expect(await wait { pane.received.contains(where: Self.isSomeSelection) })
    }

    @Test func endSearchClears() async throws {
        let pane = try openPane()
        defer { pane.close() }
        try run("echo warn", in: pane.view)
        #expect(try bind("search:warn", in: pane.view))
        #expect(
            await wait {
                pane.received.contains(where: Self.isSearchTotalOfAtLeastTwo) || pane.received.contains(.searchTotal(1))
            })

        #expect(try bind("end_search", in: pane.view))

        #expect(await wait { pane.received.last(where: Self.isSearchTotal) == .searchTotal(nil) })
    }

    @Test(arguments: [
        "select_all", "clear_screen", "scroll_page_up",
        "scroll_page_down", "scroll_to_top", "scroll_to_bottom", "jump_to_prompt:-1", "jump_to_prompt:1",
        "increase_font_size:1", "decrease_font_size:1", "reset_font_size",
    ])
    func bindingActionIsAccepted(_ action: String) async throws {
        let pane = try openPane()
        defer { pane.close() }
        #expect(await wait { !visible(pane.view).isEmpty })

        #expect(try bind(action, in: pane.view))
    }

    @Test func visibleTextContainsOutput() async throws {
        let pane = try openPane()
        defer { pane.close() }

        try run("echo hola-smalti", in: pane.view)

        #expect(await wait { visible(pane.view).contains("hola-smalti\n") })
    }

    @Test func passwordPromptRequestsSecureInput() async throws {
        let pane = try openPane()
        defer { pane.close() }
        #expect(await wait { !visible(pane.view).isEmpty })

        try run("read -s x", in: pane.view)

        #expect(await wait { pane.received.contains(.secureInputRequested(true)) })
    }

    @Test func commandHoverOverLinkReportsTheURL() async throws {
        let pane = try openPane()
        defer { pane.close() }
        try run("clear; echo https://example.com/smalti", in: pane.view)
        #expect(await wait { visible(pane.view).contains("example.com/smalti\n") })
        let prompt = try #require(pane.view.cursorCell)
        let surface = try #require(pane.view.surface)

        // `clear` leaves the URL on the first row, 10 cells in, past the padding. libghostty resolves the link under
        // the pointer on a later frame, so the pointer keeps moving over the URL until it reports it.
        let row = prompt.size.height / 2
        let hovered = await wait {
            ghostty_surface_mouse_pos(surface, prompt.size.width * 10, row, GHOSTTY_MODS_SUPER)
            ghostty_surface_mouse_pos(surface, prompt.size.width * 11, row, GHOSTTY_MODS_SUPER)
            return pane.received.contains(.linkHovered("https://example.com/smalti"))
        }

        #expect(hovered)
    }

    /// Copy and paste are not run here (they touch the user's clipboard); libghostty parses them as keybinds, which
    /// validates the same action names Smalti sends.
    @Test(arguments: TerminalActionBinding.clipboardActions)
    func clipboardActionNameIsValid(_ action: String) throws {
        let file = work.appending(path: "kb-\(UUID()).conf")

        _ = try GhosttyConfig.load(text: "keybind = super+y=\(action)\n", writingTo: file)
    }

    @Test func invalidActionNameIsRejectedByTheConfig() {
        let file = work.appending(path: "kb-bad.conf")

        #expect(throws: TerminalEngineError.self) {
            _ = try GhosttyConfig.load(text: "keybind = super+y=copy_to_clipboard:bogus\n", writingTo: file)
        }
    }

    @Test func unknownBindingActionReportsFailure() async throws {
        let pane = try openPane()
        defer { pane.close() }
        #expect(await wait { !visible(pane.view).isEmpty })

        #expect(!pane.view.bind("no_such_action"))
        #expect(pane.view.bind("select_all"))
    }
}
