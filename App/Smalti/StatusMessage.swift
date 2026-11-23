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
