import AppKit
import GhosttyKit
import SmaltiCore

/// `TerminalEngine` backed by libghostty: one `GhosttySurfaceView` per pane.
@MainActor
public final class GhosttyTerminalEngine: TerminalEngine {
    private let runtime: GhosttyRuntime
    private var views: [PaneID: GhosttySurfaceView] = [:]

    public init(runtime: GhosttyRuntime) {
        self.runtime = runtime
    }

    /// Fails when the working directory is gone (libghostty would start the shell elsewhere without saying so), so
    /// a restore can fall back to the workspace root or the home directory.
    public func open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError) {
        let path = spec.workingDirectory.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .surfaceCreationFailed(workingDirectory: path, reason: "no such directory")
        }
        views[pane] = try GhosttySurfaceView(app: runtime.app, spec: prepared(spec, for: pane))
    }

    /// Where a restored pane's saved scrollback waits for its launcher (owner-only, removed once printed).
    func restoreFile(for pane: PaneID) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-restore-\(pane).txt")
    }

    /// The spec as libghostty receives it: a pane with saved scrollback starts through `RestoreLauncher`, and a
    /// pane that restores its history says so to the shell (`SMALTI_RESTORE_HISTORY`, read by Smalti's zsh hook).
    func prepared(_ spec: TerminalSessionSpec, for pane: PaneID) -> TerminalSessionSpec {
        guard let restoration = spec.restoration else { return spec }
        var environment = spec.environment
        if restoration.restoresHistory { environment["SMALTI_RESTORE_HISTORY"] = "1" }
        var command = spec.command
        if let scrollback = restoration.scrollback, writeRestoreFile(scrollback, for: pane) {
            environment[RestoreLauncher.fileVariable] = restoreFile(for: pane).path(percentEncoded: false)
            command = .custom(RestoreLauncher.command(shell: spec.command, banner: banner(restoration.savedAt)))
        }
        return TerminalSessionSpec(
            workingDirectory: spec.workingDirectory, command: command, environment: environment,
            restoration: restoration, initialInput: spec.initialInput)
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
