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
            text: String(localized: "No room for another pane: minimum \(Int(minimum.width)) × \(Int(minimum.height))"),
            isTransient: true)
    }

    /// Same wording as F0's dialog, now in the status bar so the window stays.
    static func failedStart(exitCode: Int?) -> StatusMessage {
        let code = exitCode.map { String(localized: " (code \($0))") } ?? ""
        return StatusMessage(
            text: String(
                localized: "The shell exited at startup\(code). Check the shell command and its startup files."),
            isTransient: true)
    }

    /// File name instead of the full path: the bar is one short line.
    static func invalidConfig(_ error: ConfigError) -> StatusMessage {
        let short = error.located(in: URL(filePath: error.file).lastPathComponent)
        return StatusMessage(text: short.summary(.current), isTransient: false)
    }

    /// Shown once per distinct reason by `SessionKeeper`; the session keeps trying at the next change.
    /// F5: what reloading the files noticed but still applied (keys repeated in both files).
    static func configWarning(_ text: String) -> StatusMessage {
        StatusMessage(text: text, isTransient: true)
    }

    // F7.5: agent guards.
    static let commandApproved = StatusMessage(text: String(localized: "Command approved"), isTransient: true)
    static let commandRejected = StatusMessage(text: String(localized: "Command rejected"), isTransient: true)
    /// Review 2: chosen in ⌘K after it expired or was decided elsewhere.
    static let approvalGone = StatusMessage(
        text: String(localized: "That command no longer awaits approval"), isTransient: true)
    static let noApprovalWaiting = StatusMessage(
        text: String(localized: "No commands are waiting in this pane (⌘J jumps to the waiting agent)"),
        isTransient: true)

    static func secretsProtected(_ project: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Secrets protected in \(project)"), isTransient: true)
    }

    static func secretsUnprotected(_ project: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Secret protection removed in \(project)"), isTransient: true)
    }

    static func secretsFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: reason, isTransient: true)
    }

    static func secretBlocked(_ path: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Smalti blocked reading \(path)"), isTransient: true)
    }

    static func sessionSaveFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t save the session: \(reason)"), isTransient: true)
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

    static let nobodyWaiting = StatusMessage(text: String(localized: "No agent is waiting for you"), isTransient: true)

    static let notificationsDisabled = StatusMessage(
        text: String(localized: "Notifications are off in macOS; the state stays in the panes"), isTransient: true)

    /// Another instance of this build owns the socket.
    static let agentSocketInUse = StatusMessage(
        text: String(
            localized: "Another Smalti window already receives Claude’s events; this one won’t show their state"),
        isTransient: true)

    static func agentSocketFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t open Claude’s event channel: \(reason)"), isTransient: true)
    }

    static func layoutSaveFailed(_ name: String, reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t save the layout “\(name)”: \(reason)"), isTransient: true)
    }

    static func layoutRestoreFailed(_ name: String, reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t restore the layout “\(name)”: \(reason)"), isTransient: true)
    }

    static func layoutSaved(_ name: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Layout “\(name)” saved"), isTransient: true)
    }

    /// F7: the OTLP receiver could not listen; panes then get no telemetry variables.
    static func telemetryReceiverFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t start the telemetry receiver: \(reason)"), isTransient: true)
    }

    /// F7: shared layouts.
    static func layoutExported(_ name: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Layout “\(name)” exported"), isTransient: true)
    }

    static func layoutExportFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t export the layout: \(reason)"), isTransient: true)
    }

    static func layoutImported(_ name: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Layout “\(name)” imported"), isTransient: true)
    }

    static func layoutImportFailed(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t import the layout: \(reason)"), isTransient: true)
    }

    /// A saved layout's agent session already runs in another pane, so that pane opened a plain shell.
    static func sessionAlreadyOpen(_ session: String) -> StatusMessage {
        StatusMessage(
            text: String(localized: "Session \(session.prefix(8)) is already open in another pane"), isTransient: true)
    }

    /// F4.5 "Mostrar registros…": the file could not be written.
    static func logsFailed(_ path: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t save the logs in \(path)"), isTransient: true)
    }

    /// F4.5 ⌘,: the template could not be written where the config lives.
    static func configTemplateFailed(_ path: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t create \(path)"), isTransient: true)
    }

    static func unreadableSession(_ reason: String) -> StatusMessage {
        StatusMessage(text: String(localized: "Couldn’t read the previous session: \(reason)"), isTransient: true)
    }

    /// F7.6: the session on disk is from a newer Smalti; this one leaves it alone (shown once, at launch).
    static func newerSession(_ version: Int) -> StatusMessage {
        StatusMessage(
            text: SaveOutcome.keptNewer(version: version).message(.current) ?? "", isTransient: false)
    }

    static func restoreFailures(first: String, count: Int) -> StatusMessage {
        let more = count > 1 ? String(localized: " (and \(count - 1) more)") : ""
        return StatusMessage(text: String(localized: "Not everything was restored: \(first)\(more)"), isTransient: true)
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
