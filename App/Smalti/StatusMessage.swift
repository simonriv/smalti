import Foundation
import SmaltiCore

/// A line the status bar shows instead of `<workspace> · N paneles · <layout>`. Texts in Spanish, as the UI.
struct StatusMessage: Equatable {
    /// How long a transient message stays (decided by Simón, 2026-11-22).
    static let transientDuration: Duration = .seconds(4)

    let text: String
    /// Transient messages clear themselves; persistent ones (an invalid config) stay until the next reload.
    let isTransient: Bool

    static func paneTooSmall(minimum: Size) -> StatusMessage {
        StatusMessage(
            text: "No cabe otro panel: mínimo \(Int(minimum.width)) × \(Int(minimum.height))", isTransient: true)
    }

    /// Same wording as F0's dialog, now in the status bar so the window stays.
    static func failedStart(exitCode: Int?) -> StatusMessage {
        let code = exitCode.map { " (código \($0))" } ?? ""
        return StatusMessage(
            text: "El shell terminó al iniciar\(code). Revisa el comando del shell y sus archivos de inicio.",
            isTransient: true)
    }

    /// File name instead of the full path: the bar is one short line.
    static func invalidConfig(_ error: ConfigError) -> StatusMessage {
        let short = ConfigError(
            file: URL(filePath: error.file).lastPathComponent, line: error.line, key: error.key, reason: error.reason)
        return StatusMessage(text: short.summary, isTransient: false)
    }

    /// Shown once per distinct reason by `SessionKeeper`; the session keeps trying at the next change.
    /// F5: what reloading the files noticed but still applied (keys repeated in both files).
    static func configWarning(_ text: String) -> StatusMessage {
        StatusMessage(text: text, isTransient: true)
    }

    static func sessionSaveFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo guardar la sesión: \(reason)", isTransient: true)
    }

    /// The result line of installing or uninstalling the Claude Code integration.
    static func integration(_ line: String) -> StatusMessage {
        StatusMessage(text: line, isTransient: true)
    }

    /// F6: what opening a saved session could not do as asked (folder gone, no fork).
    static func harnessSession(_ text: String) -> StatusMessage {
        StatusMessage(text: text, isTransient: true)
    }

    /// F6: what "Abrir en Neovim" could not do (nothing edited yet).
    static func editor(_ text: String) -> StatusMessage {
        StatusMessage(text: text, isTransient: true)
    }

    /// The observatory could not read Claude's transcripts; it keeps showing what it read before.
    static func transcriptsUnreadable(_ message: String) -> StatusMessage {
        StatusMessage(text: message, isTransient: true)
    }

    static let nobodyWaiting = StatusMessage(text: "Ningún agente te espera", isTransient: true)

    static let notificationsDisabled = StatusMessage(
        text: "Notificaciones desactivadas en macOS; el estado sigue en los paneles", isTransient: true)

    /// Another instance of this build owns the socket.
    static let agentSocketInUse = StatusMessage(
        text: "Otra ventana de Smalti recibe ya los avisos de Claude; esta no mostrará su estado", isTransient: true)

    static func agentSocketFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo abrir el canal de avisos de Claude: \(reason)", isTransient: true)
    }

    static func layoutSaveFailed(_ name: String, reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo guardar el layout “\(name)”: \(reason)", isTransient: true)
    }

    static func layoutRestoreFailed(_ name: String, reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo restaurar el layout “\(name)”: \(reason)", isTransient: true)
    }

    static func layoutSaved(_ name: String) -> StatusMessage {
        StatusMessage(text: "Layout “\(name)” guardado", isTransient: true)
    }

    /// F7: the OTLP receiver could not listen; panes then get no telemetry variables.
    static func telemetryReceiverFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo arrancar el receptor de telemetría: \(reason)", isTransient: true)
    }

    /// F7: shared layouts.
    static func layoutExported(_ name: String) -> StatusMessage {
        StatusMessage(text: "Layout “\(name)” exportado", isTransient: true)
    }

    static func layoutExportFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo exportar el layout: \(reason)", isTransient: true)
    }

    static func layoutImported(_ name: String) -> StatusMessage {
        StatusMessage(text: "Layout “\(name)” importado", isTransient: true)
    }

    static func layoutImportFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo importar el layout: \(reason)", isTransient: true)
    }

    /// A saved layout's agent session already runs in another pane, so that pane opened a plain shell.
    static func sessionAlreadyOpen(_ session: String) -> StatusMessage {
        StatusMessage(text: "La sesión \(session.prefix(8)) ya está abierta en otro panel", isTransient: true)
    }

    /// F4.5 "Mostrar registros…": the file could not be written.
    static func logsFailed(_ path: String) -> StatusMessage {
        StatusMessage(text: "No se pudieron guardar los registros en \(path)", isTransient: true)
    }

    /// F4.5 ⌘,: the template could not be written where the config lives.
    static func configTemplateFailed(_ path: String) -> StatusMessage {
        StatusMessage(text: "No se pudo crear \(path)", isTransient: true)
    }

    static func unreadableSession(_ reason: String) -> StatusMessage {
        StatusMessage(text: "No se pudo leer la sesión anterior: \(reason)", isTransient: true)
    }

    static func restoreFailures(first: String, count: Int) -> StatusMessage {
        let more = count > 1 ? " (y \(count - 1) más)" : ""
        return StatusMessage(text: "No se restauró todo: \(first)\(more)", isTransient: true)
    }

    static func engineFailure(_ error: TerminalEngineError) -> StatusMessage {
        StatusMessage(text: EngineErrorText.describe(error), isTransient: true)
    }
}

/// Human text for engine errors, shared by the startup alert and the status bar.
enum EngineErrorText {
    static func describe(_ error: TerminalEngineError) -> String {
        switch error {
        case .engineStartFailed(let reason): reason
        case .configurationInvalid(let diagnostics): diagnostics.joined(separator: "\n")
        case .surfaceCreationFailed(let directory, let reason): "\(directory): \(reason)"
        }
    }
}
