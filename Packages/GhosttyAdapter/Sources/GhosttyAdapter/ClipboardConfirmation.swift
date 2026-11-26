import AppKit
import GhosttyKit
import SmaltiCore

/// What Smalti does when libghostty asks to confirm a clipboard access.
enum ClipboardConfirmation: Equatable {
    case askUser
    case deny

    /// Pastes that libghostty flags as unsafe (multi-line without bracketed paste) ask the user; reads and
    /// writes requested by programs (OSC 52, Kitty) are denied in F0.
    static func decision(for request: ghostty_clipboard_request_e) -> ClipboardConfirmation {
        request == GHOSTTY_CLIPBOARD_REQUEST_PASTE ? .askUser : .deny
    }

    /// The `text/plain` contents libghostty would paste, copied out of the borrowed C payload.
    static func pasteText(from confirm: ghostty_clipboard_confirm_s) -> String? {
        guard let contents = confirm.contents else { return nil }
        return (0..<confirm.contents_len).lazy.map { contents[$0] }
            .first { $0.mime.map { String(cString: $0) } == "text/plain" }
            .map { entry in
                entry.data.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: entry.len), as: UTF8.self) }
                    ?? ""
            }
    }

    /// Asks before pasting text with line breaks into a program that may run each line.
    @MainActor
    static func userApprovesPaste(of text: String, texts: TerminalTexts) -> Bool {
        let alert = NSAlert()
        alert.messageText = texts.pasteTitle
        alert.informativeText = texts.pasteMessage + "\n\n" + preview(of: text)
        alert.addButton(withTitle: texts.pasteButton)
        alert.addButton(withTitle: texts.cancelButton)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static let previewLineLimit = 6

    private static func preview(of text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = lines.prefix(previewLineLimit).joined(separator: "\n")
        return lines.count > previewLineLimit ? shown + "\n…" : shown
    }
}
