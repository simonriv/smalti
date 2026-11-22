import GhosttyKit
import Testing

@testable import GhosttyAdapter

/// Review finding #1: a multi-line paste into a program without bracketed paste must ask, not vanish.
@Suite("Clipboard confirmation")
struct ClipboardConfirmationTests {
    @Test func pasteAsksTheUser() {
        #expect(ClipboardConfirmation.decision(for: GHOSTTY_CLIPBOARD_REQUEST_PASTE) == .askUser)
    }

    @Test(arguments: [
        GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ, GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE,
        GHOSTTY_CLIPBOARD_REQUEST_KITTY_READ, GHOSTTY_CLIPBOARD_REQUEST_KITTY_WRITE, GHOSTTY_CLIPBOARD_REQUEST_LIST,
    ])
    func programReadsAndWritesAreDenied(_ request: ghostty_clipboard_request_e) {
        #expect(ClipboardConfirmation.decision(for: request) == .deny)
    }

    @Test func extractsTheTextPlainContentToConfirm() {
        let text = "echo uno\necho dos\n"
        let bytes = Array(text.utf8)
        let extracted = "image/png".withCString { png in
            "text/plain".withCString { plain in
                bytes.withUnsafeBufferPointer { buffer in
                    buffer.withMemoryRebound(to: CChar.self) { data in
                        let contents = [
                            ghostty_clipboard_content_s(mime: png, data: nil, len: 0),
                            ghostty_clipboard_content_s(mime: plain, data: data.baseAddress, len: bytes.count),
                        ]
                        return contents.withUnsafeBufferPointer { list in
                            ClipboardConfirmation.pasteText(
                                from: ghostty_clipboard_confirm_s(
                                    contents: list.baseAddress, contents_len: list.count, available: nil,
                                    available_len: 0, name: nil, can_remember: false))
                        }
                    }
                }
            }
        }

        #expect(extracted == text)
    }

    @Test func noTextPlainMeansNothingToConfirm() {
        let confirm = ghostty_clipboard_confirm_s(
            contents: nil, contents_len: 0, available: nil, available_len: 0, name: nil, can_remember: false)

        #expect(ClipboardConfirmation.pasteText(from: confirm) == nil)
    }
}
