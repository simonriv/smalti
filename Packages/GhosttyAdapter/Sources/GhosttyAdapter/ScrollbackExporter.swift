import Foundation
import GhosttyKit
import SmaltiCore
import Synchronization

/// Exports a surface's whole screen (history and visible part) as VT text through libghostty's
/// `write_screen_file:open,vt`. libghostty writes a temporary file and asks the app to open it (OPEN_URL) inside the
/// same call; while an export is pending, `GhosttyRuntime` hands that path here instead of opening it.
@MainActor
enum ScrollbackExporter {
    private static let action = "write_screen_file:open,vt"
    /// Surface address → exported file path, filled by `claim` during the binding call.
    private nonisolated static let pending = Mutex<[Int: String?]>([:])
    /// The last file read and removed (tests check it is gone).
    static private(set) var lastExportedFile: String?

    /// Called by the runtime's action callback for OPEN_URL: true when the URL was an export this enum asked for.
    nonisolated static func claim(surface: Int, path: String) -> Bool {
        pending.withLock { waiting in
            guard waiting.keys.contains(surface) else { return false }
            waiting[surface] = path
            return true
        }
    }

    /// The VT export, or nil when libghostty did not produce one (alternate screen, failure, API change).
    static func exportVT(_ surface: ghostty_surface_t) -> String? {
        let address = Int(bitPattern: surface)
        pending.withLock { $0[address] = .some(nil) }
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
        let path = pending.withLock { $0.removeValue(forKey: address) ?? nil }
        guard let path else { return nil }
        defer { discard(path) }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Plain text of the whole screen through the official read API.
    static func exportPlain(_ surface: ghostty_surface_t) -> String? {
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let bytes = text.text else { return "" }
        // Safe: libghostty owns `text_len` bytes at `text` until ghostty_surface_free_text.
        return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(text.text_len)), as: UTF8.self)
    }

    /// libghostty keeps its temporary directory for the app to open. Removes the file and then that directory only
    /// if it is now empty (`rmdir` never deletes contents, whatever path a future libghostty hands over).
    static func discard(_ path: String) {
        lastExportedFile = path
        let file = URL(filePath: path)
        try? FileManager.default.removeItem(at: file)
        _ = rmdir(file.deletingLastPathComponent().path(percentEncoded: false))
    }
}
