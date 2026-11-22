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
    private var pane: Pane?
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

    private func openTerminal(in window: SmaltiWindow) throws(TerminalEngineError) {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: Bundle.main.resourceURL?.appending(path: "ghostty"))
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(theme.terminal), writingTo: Self.engineConfigFile)
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let home = try homeDirectory()
        let pane = try OpenPane(engine: engine).execute(Self.sessionSpec(in: home))
        guard let view = (engine as TerminalViewProvider).view(for: pane.id) else { return }
        window.paneContainer.embed(view)
        window.makeFirstResponder(view)
        self.engine = engine
        self.pane = pane
        paneOpenedAt = .now
        observe(engine.events(for: pane.id))
    }

    private func observe(_ events: AsyncStream<TerminalEvent>) {
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.logger.info("pane event: \(String(describing: event), privacy: .public)")
                self.pane = self.pane?.applying(event)
                if case .exited(let code) = event {
                    self.paneDidExit(code: code)
                    return
                }
            }
        }
    }

    private func paneDidExit(code: Int?) {
        let lifetime = paneOpenedAt.map { ContinuousClock.now - $0 } ?? .zero
        switch HandlePaneExit().execute(exitCode: code, lifetime: lifetime) {
        case .closePane:
            window?.close()
        case .reportFailedStart(let exitCode):
            reportFailedStart(exitCode: exitCode)
            window?.close()
        }
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
    private static func sessionSpec(in home: WorkingDirectory) -> TerminalSessionSpec {
        guard let command = UserDefaults.standard.string(forKey: "SmaltiShellCommand"), !command.isEmpty else {
            return .loginShell(in: home)
        }
        return TerminalSessionSpec(workingDirectory: home, command: .custom(command))
    }

    private func homeDirectory() throws(TerminalEngineError) -> WorkingDirectory {
        let path = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        do {
            return try WorkingDirectory(path: path)
        } catch {
            throw .surfaceCreationFailed(workingDirectory: path, reason: "home directory is not absolute")
        }
    }

    private func fail(_ error: TerminalEngineError) {
        logger.error("terminal engine failed: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Smalti no pudo iniciar la terminal"
        alert.informativeText = Self.describe(error)
        alert.runModal()
        NSApp.terminate(nil)
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
