import AppKit
import OSLog
import GhosttyKit
import SmaltiCore

/// `TerminalEngine` backed by libghostty: one `GhosttySurfaceView` per pane.
@MainActor
public final class GhosttyTerminalEngine: TerminalEngine {
    private let runtime: GhosttyRuntime
    private var views: [PaneID: GhosttySurfaceView] = [:]
    /// Where Smalti's zsh startup file lives (per-pane history); nil disables it.
    private let zshDirectory: URL?
    /// The `ZDOTDIR` the app itself was started with, handed back to the user's shell.
    private let userZdotdir: String?

    public init(runtime: GhosttyRuntime, zshDirectory: URL? = nil, userZdotdir: String? = nil) {
        self.runtime = runtime
        self.zshDirectory = zshDirectory.flatMap(Self.installZshEnv)
        self.userZdotdir = userZdotdir
    }

    /// F5.5 `[preview] hover`: whether panes report the word under the pointer; applies to open panes at once.
    public var reportsPointerWords = true {
        didSet { views.values.forEach { $0.reportsPointerWords = reportsPointerWords } }
    }

    /// The terminal padding in points (the theme's `paddingX`/`paddingY`): where the cell grid starts.
    public var gridPadding = Point(x: 0, y: 0) {
        didSet { views.values.forEach { $0.gridPadding = gridPadding } }
    }

    /// F5.5: the pane's next pointer move reports its word even if it did not change (the card was hidden for a key).
    public func forgetPointerWord(in pane: PaneID) {
        views[pane]?.forgetPointerWord()
    }

    /// Fails when the working directory is gone (libghostty would start the shell elsewhere without saying so), so
    /// a restore can fall back to the workspace root or the home directory.
    public func open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError) {
        let path = spec.workingDirectory.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .surfaceCreationFailed(workingDirectory: path, reason: .directoryMissing)
        }
        do {
            let view = try GhosttySurfaceView(app: runtime.app, spec: prepared(spec, for: pane))
            view.contextMenuProvider = { [weak self] in self?.contextMenu?(pane) }
            view.commandClick = { [weak self] word in self?.commandClick?(pane, word) ?? false }
            view.exposesCellSize = exposesCellSize
            view.reportsPointerWords = reportsPointerWords
            view.gridPadding = gridPadding
            views[pane] = view
        } catch {
            // The launcher never ran, so nobody else removes the saved scrollback.
            try? FileManager.default.removeItem(at: restoreFile(for: pane))
            throw error
        }
    }

    /// Where a restored pane's saved scrollback waits for its launcher (owner-only, removed once printed).
    func restoreFile(for pane: PaneID) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-restore-\(pane).txt")
    }

    /// The spec as libghostty receives it: a pane with saved scrollback starts through `RestoreLauncher`, and a
    /// pane that restores its history says so to the shell (`SMALTI_RESTORE_HISTORY`, read by Smalti's zsh hook).
    func prepared(_ spec: TerminalSessionSpec, for pane: PaneID) -> TerminalSessionSpec {
        var environment = spec.environment.merging(
            Self.zshChain(for: spec, zshDirectory: zshDirectory, userZdotdir: userZdotdir)
        ) { own, _ in own }
        guard let restoration = spec.restoration else {
            return TerminalSessionSpec(
                workingDirectory: spec.workingDirectory, command: spec.command, environment: environment,
                initialInput: spec.initialInput)
        }
        if restoration.restoresHistory { environment["SMALTI_RESTORE_HISTORY"] = "1" }
        var command = spec.command
        if let scrollback = restoration.scrollback, writeRestoreFile(scrollback, for: pane) {
            environment[RestoreLauncher.fileVariable] = restoreFile(for: pane).path(percentEncoded: false)
            environment[RestoreLauncher.bannerVariable] = banner(restoration.savedAt)
            command = .custom(RestoreLauncher.command(shell: spec.command))
        }
        return TerminalSessionSpec(
            workingDirectory: spec.workingDirectory, command: command, environment: environment,
            restoration: restoration, initialInput: spec.initialInput)
    }

    /// Variables that put Smalti's zsh file in libghostty's chain, for panes with a history file or an input socket
    /// (F4). `ZDOTDIR` itself is left to libghostty (a pane variable would replace its integration directory).
    nonisolated static func zshChain(for spec: TerminalSessionSpec, zshDirectory: URL?, userZdotdir: String?)
        -> [String: String]
    {
        guard let zshDirectory,
            spec.environment["SMALTI_HISTORY_FILE"] != nil || spec.environment["SMALTI_INPUT_SOCKET"] != nil
        else { return [:] }
        var chain = ["GHOSTTY_ZSH_ZDOTDIR": zshDirectory.path(percentEncoded: false)]
        if let userZdotdir { chain["SMALTI_USER_ZDOTDIR"] = userZdotdir }
        return chain
    }

    /// False when the file cannot be written: the pane then starts without its scrollback.
    private func writeRestoreFile(_ scrollback: Scrollback, for pane: PaneID) -> Bool {
        let file = restoreFile(for: pane)
        let created = FileManager.default.createFile(
            atPath: file.path(percentEncoded: false), contents: Data(scrollback.text.utf8),
            attributes: [.posixPermissions: 0o600])
        return created
    }

    private func banner(_ savedAt: Date) -> String {
        RestoreBanner.text(savedAt: savedAt, calendar: .current)
    }

    /// Without the file, panes still work but keep only the shared history; the failure is logged.
    private static func installZshEnv(_ directory: URL) -> URL? {
        do {
            return try SmaltiZshEnv.install(in: directory)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "smalti", category: "engine")
                .error("could not write the per-pane history file: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Off only in tests, to exercise the plain-text fallback.
    var exportsVT = true

    public func close(_ pane: PaneID) {
        guard let view = views.removeValue(forKey: pane) else { return }
        view.shutDown()
        view.removeFromSuperview()
    }

    public func show(_ pane: PaneID) {
        views[pane]?.show()
    }

    public func hide(_ pane: PaneID) {
        views[pane]?.hide()
    }

    public func events(for pane: PaneID) -> AsyncStream<TerminalEvent> {
        views[pane]?.events ?? AsyncStream { $0.finish() }
    }

    /// The AppKit view that renders `pane`; the app embeds it. Not part of the domain port.
    public func view(for pane: PaneID) -> NSView? {
        views[pane]
    }

    /// Whether the pane's shell is at its prompt (OSC 133), not running a command or a full-screen program.
    public func isAtPrompt(_ pane: PaneID) -> Bool {
        views[pane]?.isAtPrompt ?? false
    }

    /// Presses Return in the pane, as if typed.
    public func pressReturn(_ pane: PaneID) {
        views[pane]?.pressReturn()
    }

    /// The cursor's cell in the pane's view, in points from its top-left corner.
    public func cursorCell(_ pane: PaneID) -> Rect? {
        views[pane]?.cursorCell
    }

    // MARK: - F4.5

    /// The terminal's menu for a right click or ⌃click on `pane`; nil shows none. The app builds it.
    public var contextMenu: ((PaneID) -> NSMenu?)?
    /// F6: ⌘-click on a word of a pane; true when the app took it (a file opened in Neovim), so the terminal does
    /// not also open it as a link.
    public var commandClick: ((PaneID, String) -> Bool)?

    /// UI tests only: each terminal states its cell size as its accessibility title ("celda 8 × 21").
    public var exposesCellSize = false

    public func perform(_ action: TerminalAction, in pane: PaneID) {
        guard let view = views[pane] else { return }
        let name = TerminalActionBinding.action(for: action)
        if !view.bind(name) {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "smalti", category: "engine")
                .error("libghostty did not run \(name, privacy: .public)")
        }
    }

    public func search(_ text: String, in pane: PaneID) {
        views[pane]?.bind(TerminalActionBinding.search(text))
    }

    public func navigateSearch(_ direction: SearchDirection, in pane: PaneID) {
        views[pane]?.bind(TerminalActionBinding.navigate(direction))
    }

    public func endSearch(in pane: PaneID) {
        views[pane]?.bind(TerminalActionBinding.endSearch)
    }

    public func visibleText(of pane: PaneID) -> String {
        views[pane]?.visibleText ?? ""
    }

    public func foregroundProcess(of pane: PaneID) -> SmaltiCore.ForegroundProcess? {
        views[pane]?.currentForegroundProcess
    }
}

extension GhosttyTerminalEngine: ScrollbackSource {
    /// The pane's whole screen, with colours when libghostty can export them, else as plain text.
    public func scrollback(of pane: PaneID, lastLines: Int) throws(ScrollbackError) -> Scrollback {
        guard let surface = views[pane]?.surface else { throw .unavailable(pane: pane, reason: "no such pane") }
        if exportsVT, let text = ScrollbackExporter.exportVT(surface) {
            return Scrollback(text: ScrollbackTrimmer.lastLines(text, count: lastLines), format: .vt)
        }
        guard let text = ScrollbackExporter.exportPlain(surface) else {
            throw .unavailable(pane: pane, reason: "libghostty could not read the screen")
        }
        return Scrollback(text: ScrollbackTrimmer.lastLines(text, count: lastLines), format: .plain)
    }
}
