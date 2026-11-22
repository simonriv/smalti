import AppKit
import GhosttyAdapter
import OSLog
import SmaltiCore

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let theme = Theme.obsidian
    private let logger = Logger(subsystem: "dev.simonriv.smalti", category: "engine")
    private var window: SmaltiWindow?
    private var engine: GhosttyTerminalEngine?
    private var workspaces: WorkspaceSet?
    private var paneOpenedAt: ContinuousClock.Instant?

    func showMainWindow() {
        let window = SmaltiWindow(theme: theme)
        window.makeKeyAndOrderFront(nil)
        WindowGlass.apply(blurRadius: theme.window.blurRadius, to: window)
        self.window = window
        do {
            try openTerminal(in: window)
        } catch {
            fail(error)
        }
    }

    private func openTerminal(in window: SmaltiWindow) throws(OpenPaneError) {
        let engine = try makeEngine()
        let home = try homeDirectory()
        var set = WorkspaceSet(
            first: .empty(name: home.lastComponent, rootDirectory: home, layout: DwindleLayout()))
        window.contentView?.layoutSubtreeIfNeeded()
        let request = OpenPaneRequest(
            shell: Self.shellCommand(), geometry: .standard(area: Self.area(of: window.paneContainer)))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let open = OpenPane(engine: engine, version: version)
        let pane = try open.execute(request, in: &set)
        guard let view = (engine as TerminalViewProvider).view(for: pane) else { return }
        window.paneContainer.embed(view)
        window.makeFirstResponder(view)
        self.engine = engine
        workspaces = set
        paneOpenedAt = .now
        observe(engine.events(for: pane), of: pane)
    }

    private func makeEngine() throws(OpenPaneError) -> GhosttyTerminalEngine {
        do {
            try GhosttyProcess.ensureInitialized(
                resourcesDirectory: Bundle.main.resourceURL?.appending(path: "ghostty"))
            let config = try GhosttyConfig.load(
                text: GhosttyConfigText.render(theme.terminal), writingTo: Self.engineConfigFile)
            return GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        } catch {
            throw .engine(error)
        }
    }

    private func observe(_ events: AsyncStream<TerminalEvent>, of pane: PaneID) {
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.logger.info("pane event: \(String(describing: event), privacy: .public)")
                self.apply(event, to: pane)
                if case .exited(let code) = event {
                    self.paneDidExit(pane, code: code)
                    return
                }
                if event == .closeRequested {
                    self.paneDidRequestClose(pane)
                    return
                }
            }
        }
    }

    private func apply(_ event: TerminalEvent, to pane: PaneID) {
        guard let set = workspaces, let owner = set.workspace(containing: pane) else { return }
        workspaces = set.updating(owner) { $0.applying(event, to: pane) }
    }

    private func paneDidExit(_ pane: PaneID, code: Int?) {
        guard let engine, var set = workspaces else { return }
        let lifetime = paneOpenedAt.map { ContinuousClock.now - $0 } ?? .zero
        let exit = PaneExit(pane: pane, exitCode: code, lifetime: lifetime)
        let outcome = HandlePaneExit(engine: engine).execute(exit, in: &set)
        workspaces = set
        switch outcome {
        case .alreadyClosed:
            return
        case .closed:
            break
        case .closedAfterFailedStart(let exitCode):
            reportFailedStart(exitCode: exitCode)
        }
        if set.active.panes.isEmpty { window?.close() }
    }

    /// The terminal asked to close its pane with the process still running; the engine never closes on its own.
    private func paneDidRequestClose(_ pane: PaneID) {
        guard let engine, var set = workspaces else { return }
        _ = ClosePane(engine: engine).execute(pane, in: &set)
        workspaces = set
        if set.active.panes.isEmpty { window?.close() }
    }

    private func reportFailedStart(exitCode: Int?) {
        let alert = NSAlert()
        alert.messageText = "El shell terminó al iniciar"
        alert.informativeText =
            (exitCode.map { "Código de salida: \($0). " } ?? "")
            + "Revisa el comando del shell y sus archivos de inicio (por ejemplo ~/.zshrc)."
        alert.addButton(withTitle: "Cerrar")
        alert.runModal()
    }

    /// Login shell by default. `-SmaltiShellCommand <command>` (launch argument) overrides it; UI tests use it
    /// to run a shell without startup files. F1 moves this to `[shell] command` in config.toml.
    private static func shellCommand() -> TerminalCommand {
        guard let command = UserDefaults.standard.string(forKey: "SmaltiShellCommand"), !command.isEmpty else {
            return .loginShell
        }
        return .custom(command)
    }

    private static func area(of container: NSView) -> Rect {
        Rect(x: 0, y: 0, width: container.bounds.width, height: container.bounds.height)
    }

    private func homeDirectory() throws(OpenPaneError) -> WorkingDirectory {
        let path = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        do {
            return try WorkingDirectory(path: path)
        } catch {
            throw .engine(.surfaceCreationFailed(workingDirectory: path, reason: "home directory is not absolute"))
        }
    }

    private func fail(_ error: OpenPaneError) {
        logger.error("terminal engine failed: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Smalti no pudo iniciar la terminal"
        alert.informativeText = Self.describe(error)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private static func describe(_ error: OpenPaneError) -> String {
        switch error {
        case .paneTooSmall(let minimum):
            "No cabe un panel de \(Int(minimum.width)) × \(Int(minimum.height)) pt."
        case .engine(let engineError):
            describe(engineError)
        }
    }

    private static func describe(_ error: TerminalEngineError) -> String {
        switch error {
        case .engineStartFailed(let reason): reason
        case .configurationInvalid(let diagnostics): diagnostics.joined(separator: "\n")
        case .surfaceCreationFailed(let directory, let reason): "\(directory): \(reason)"
        }
    }

    private static var engineConfigFile: URL {
        URL.applicationSupportDirectory.appending(path: "Smalti/ghostty.conf")
    }
}
