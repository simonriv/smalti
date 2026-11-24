import AppKit
import SmaltiCore

/// The question `CloseGuard` decided, as a sheet on the window: "Cerrar" (↩) or "Cancelar" (esc).
enum CloseConfirmation {
    @MainActor
    static func ask(_ question: CloseQuestion, in window: NSWindow, then answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = question.title
        alert.informativeText = question.detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cerrar")
        let cancel = alert.addButton(withTitle: "Cancelar")
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in answer(response == .alertFirstButtonReturn) }
    }
}
