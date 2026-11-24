import AppKit
import Foundation
import GhosttyKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Spec F5.5: the word under the mouse pointer, as libghostty cuts it, with its frame in the pane's points.
@Suite("Pointer word geometry")
struct PointerWordGeometryTests {
    private let cell = Size(width: 8, height: 20)

    @Test func frameSpansTheWordFromItsBaseline() {
        let frame = PointerWordGeometry.frame(text: "foto.png", baseline: Point(x: 16, y: 56), cell: cell)

        #expect(frame == Rect(x: 16, y: 40, width: 64, height: 20))
    }

    @Test func wideCharactersTakeTwoCells() {
        let frame = PointerWordGeometry.frame(text: "写真.png", baseline: Point(x: 0, y: 16), cell: cell)

        #expect(frame.size.width == 64)
    }

    @Test func pointMapsToItsCell() {
        #expect(PointerWordGeometry.cell(at: Point(x: 17, y: 41), cell: cell) == PointerCell(column: 2, row: 2))
        #expect(PointerWordGeometry.cell(at: Point(x: 23.9, y: 59.9), cell: cell) == PointerCell(column: 2, row: 2))
    }

    @Test func emptyCellSizeHasNoCell() {
        #expect(PointerWordGeometry.cell(at: Point(x: 1, y: 1), cell: Size(width: 0, height: 0)) == nil)
    }
}

/// Against a real surface: `zsh -f` prints names, the pointer moves over them.
@MainActor
@Suite("Pointer word on a surface", .serialized)
struct PointerWordSurfaceTests {
    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-f55-\(UUID())")
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
        private(set) var words: [PointerWord?] = []
        private var reader: Task<Void, Never>?

        init(view: GhosttySurfaceView, window: NSWindow) {
            self.view = view
            self.window = window
            reader = Task { @MainActor [weak self] in
                guard let stream = self?.view.events else { return }
                for await event in stream {
                    if case .pointerWordChanged(let word) = event { self?.words.append(word) }
                }
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
        (command + "\r").withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// `clear` leaves the output on the first row: `foto.png otro.jpg shots/a.png`.
    private func printNames(in pane: Pane) async throws -> Rect {
        try run("clear; echo foto.png otro.jpg shots/a.png", in: pane.view)
        // The typed line echoes the names too: wait until `clear` ran and they are the first row.
        #expect(await wait { (pane.view.visibleText ?? "").hasPrefix("foto.png otro.jpg shots/a.png\n") })
        return try #require(pane.view.cursorCell)
    }

    private func move(_ pane: Pane, toColumn column: Double, cell: Rect) {
        pane.view.pointerMoved(to: Point(x: cell.size.width * (column + 0.5), y: cell.size.height / 2))
    }

    @Test func wordUnderPointerIsReported() async throws {
        let pane = try openPane()
        defer { pane.close() }
        let cell = try await printNames(in: pane)

        move(pane, toColumn: 2, cell: cell)

        #expect(await wait { pane.words.last??.text == "foto.png" })
        let frame = try #require(pane.words.last??.frame)
        #expect(frame.size.width == cell.size.width * 8)
    }

    @Test func pathWithSlashIsOneWord() async throws {
        let pane = try openPane()
        defer { pane.close() }
        let cell = try await printNames(in: pane)

        move(pane, toColumn: 20, cell: cell)

        #expect(await wait { pane.words.last??.text == "shots/a.png" })
    }

    @Test func movingInsideTheSameWordReportsOnce() async throws {
        let pane = try openPane()
        defer { pane.close() }
        let cell = try await printNames(in: pane)

        move(pane, toColumn: 1, cell: cell)
        move(pane, toColumn: 3, cell: cell)
        move(pane, toColumn: 3, cell: cell)
        _ = await wait({ false }, timeout: 0.2)

        #expect(pane.words.compactMap { $0?.text } == ["foto.png"])
    }

    @Test func leavingViewSendsNil() async throws {
        let pane = try openPane()
        defer { pane.close() }
        let cell = try await printNames(in: pane)
        move(pane, toColumn: 2, cell: cell)
        #expect(await wait { pane.words.last??.text == "foto.png" })

        pane.view.pointerLeft()

        #expect(await wait { pane.words.last == .some(nil) })
    }

    @Test func disabledSendsNothing() async throws {
        let pane = try openPane()
        defer { pane.close() }
        pane.view.reportsPointerWords = false
        let cell = try await printNames(in: pane)

        move(pane, toColumn: 2, cell: cell)
        _ = await wait({ false }, timeout: 0.2)

        #expect(pane.words.isEmpty)
    }
}
